import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import 'caps_holder.dart';
import '../core/caps.dart';
import 'file_cache.dart';
import 'library.dart';
import 'presence.dart';
import 'offline.dart';
import 'obs_overlay.dart';
import 'player.dart';
import 'settings.dart';

/// Everything that exists while someone is signed in.
class Services {
  Services(this.api, this.settings, {this.offlineOnly = false})
      : offline = OfflineStore(api, settings),
        library = Library(api) {
    _back = api.offlineChanges.listen((off) {
      if (!off) library.refresh(); // the server answered again
    });
    library.downloadOnLike = () => settings.likeDownloadsToServer && caps.has('like-download');
    library.has = caps.has;
    player = PlayerController(api, library, offline, settings);
    player.has = caps.has;
    if (ObsOverlay.supported) overlay = ObsOverlay.forPlayer(api, player, settings);
  }

  ObsOverlay? overlay;
  final Api api;
  final Settings settings;

  /// Signed out, but opened from the saved copies on this device: no network calls at all.
  final bool offlineOnly;
  final OfflineStore offline;
  final Library library;
  late final PlayerController player;
  PresenceService? presence;
  final CapsHolder caps = CapsHolder();

  StreamSubscription<List<ConnectivityResult>>? _net;
  StreamSubscription<bool>? _back;

  bool _none(List<ConnectivityResult> r) => r.isEmpty || r.every((x) => x == ConnectivityResult.none);

  Future<void> start() async {
    overlay?.start();
    await offline.load();
    if (offlineOnly) {
      api.setForcedOffline(true);
      try {
        caps.set(await api.capabilities()); // the saved copy of what the server offered
      } catch (_) {
        caps.set(Capabilities.generic);
      }
      await library.loadSaved();
      unawaited(player.restore());
      return;
    }
    try {
      caps.set(await api.capabilities());
    } catch (_) {
      caps.set(Capabilities.generic); // not reachable and nothing saved yet
    }
    unawaited(player.restore()); // picks up the last queue at once (Android Auto may be waiting for it)
    if (PresenceService.supported && caps.has('presence')) presence = PresenceService(api, player, settings)..start();
    await library.loadSaved(); // the last saved lists show at once, before any network call
    try {
      final c = Connectivity();
      api.setForcedOffline(_none(await c.checkConnectivity()));
      _net = c.onConnectivityChanged.listen((r) {
        final gone = _none(r);
        api.setForcedOffline(gone);
        if (!gone) library.refresh();
      });
    } catch (_) {}
    await library.refresh();
    library.startPolling();
  }

  void dispose() {
    presence?.dispose();
    overlay?.dispose();
    caps.dispose();
    _net?.cancel();
    _back?.cancel();
    player.dispose();
    library.dispose();
    api.close();
  }
}

/// Server address + login, kept on the device. Signing in creates [services].
class Session extends ChangeNotifier {
  SharedPreferences? _prefs;
  bool loaded = false;
  String server = '';
  String user = '';
  String _password = '';
  Services? services;
  StreamSubscription<void>? _authSub;
  Timer? _authTimer;

  /// Shown on the login screen after the app signed itself out.
  String? notice;
  late Settings settings;

  String get currentPassword => _password;

  bool get signedIn => services != null;

  /// Signed out but using the libraries saved on this device (see [enterOfflineMode]).
  bool offlineMode = false;

  /// Offline mode is there for anyone who has signed in on this device before.
  bool get canUseOffline => server.isNotEmpty && user.isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    settings = Settings(_prefs!);
    settings.addListener(notifyListeners);
    server = _prefs!.getString('server') ?? '';
    user = _prefs!.getString('user') ?? '';
    _password = _prefs!.getString('password') ?? '';
    if (server.isNotEmpty && user.isNotEmpty && _password.isNotEmpty) {
      try {
        await _enter(server, user, _password, verify: false);
      } catch (_) {
        // stay on the login screen with the saved address filled in
      }
    } else if (canUseOffline && _prefs!.getBool('offlineMode') == true) {
      await enterOfflineMode(); // you left it this way: carry on in offline mode
    }
    loaded = true;
    notifyListeners();
  }

  /// Throws [ApiException] with a message fit to show.
  Future<void> signIn(String serverInput, String userInput, String password) async {
    final s = normalizeServer(serverInput);
    if (s.isEmpty || userInput.trim().isEmpty || password.isEmpty) {
      throw ApiException('Fill in the server address, username and password.');
    }
    await _enter(s, userInput.trim(), password, verify: true);
    notice = null;
    await _prefs!.setString('server', s);
    await _prefs!.setString('user', userInput.trim());
    await _prefs!.setString('cacheUser', userInput.trim());
    await _prefs!.setString('password', password);
    server = s;
    user = userInput.trim();
    _password = password;
    notifyListeners();
  }

  /// Change the Navidrome username and/or password; the saved login and the open session follow.
  /// Saved copies stay under the name they were first saved with, so nothing is lost.
  Future<void> changeAccount({String? newUser, String? newPassword}) async {
    final api = services?.api;
    if (api == null || offlineMode) throw ApiException('Sign in first.');
    if (_prefs?.getString('cacheUser') == null) await _prefs?.setString('cacheUser', user);
    await api.changeAccount(newUser: newUser, newPassword: newPassword);
    // the new details are not saved: you sign in again with them (see the settings dialog)
    if (newUser != null) {
      user = newUser;
      await _prefs!.setString('user', newUser);
    }
  }

  /// Open the app without signing in: downloaded songs, saved playlists and liked songs, no server needed.
  /// Only for someone who has signed in here before (their saved copies are what it shows).
  Future<void> enterOfflineMode() async {
    if (!canUseOffline) return;
    await _prefs?.setBool('offlineMode', true);
    await _enter(server, user, '', verify: false, offlineOnly: true);
  }

  Future<void> _enter(String s, String u, String p, {required bool verify, bool offlineOnly = false}) async {
    final api = Api(server: s, user: u, password: p, cache: FileResponseCache('$s|${_prefs?.getString('cacheUser') ?? u}'));
    if (verify) {
      try {
        await api.checkLogin();
      } catch (_) {
        api.close();
        rethrow;
      }
    }
    _authSub?.cancel();
    _authTimer?.cancel();
    services?.dispose();
    final svc = Services(api, settings, offlineOnly: offlineOnly);
    if (!offlineOnly) {
      _authSub = api.authLost.listen((_) => _lostLogin(api));
      // an app left open still finds out soon that its account changed
      _authTimer = Timer.periodic(const Duration(minutes: 3), (_) => api.verifyLogin());
    }
    services = svc;
    offlineMode = offlineOnly;
    if (!offlineOnly) await _prefs?.remove('offlineMode');
    notifyListeners();
    // the first refresh must not block the UI (and must not log you out when the server is briefly away)
    svc.start();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authTimer?.cancel();
    services?.dispose();
    super.dispose();
  }

  Future<void> _lostLogin(Api api) async {
    if (services?.api != api || offlineMode) return;
    notice = 'Your account details changed. Sign in again with the new ones.';
    await signOut();
  }

  Future<void> signOut() async {
    _authSub?.cancel();
    _authTimer?.cancel();
    services?.dispose();
    services = null;
    offlineMode = false;
    _password = '';
    await _prefs?.remove('password');
    await _prefs?.remove('offlineMode');
    notifyListeners();
  }
}
