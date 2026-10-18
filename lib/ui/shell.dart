import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../platform/platform.dart';
import '../state/background_setup.dart';
import '../state/desktop_window.dart';
import '../state/download_notice.dart';
import '../state/home_widgets.dart';
import 'package:home_widget/home_widget.dart';
import '../state/offline.dart';
import '../state/global_hotkeys.dart';
import '../state/hotkeys.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../core/caps.dart';
import '../state/caps_holder.dart';
import 'library_screen.dart';
import 'now_playing.dart';
import 'mini_window.dart';
import 'search_screen.dart';
import 'server_screen.dart';
import 'settings_screen.dart';
import 'shell_navigator.dart';
import '../state/settings.dart';
import 'update_dialog.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  StreamSubscription<String>? errors;
  HotkeyService? _hotkeys;
  GlobalHotkeyService? _globalHotkeys;
  DownloadNotice? _notice;
  HomeWidgetsSync? _widgets;
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    errors = context.read<PlayerController>().errors.listen((m) {
      if (mounted) context.toast(m);
    });
    if (isDesktop) _hotkeys = HotkeyService(settings: context.read<Settings>(), run: _hotkey)..start();
    if (Platform.isWindows) _globalHotkeys = GlobalHotkeyService(settings: context.read<Settings>(), run: _globalHotkey)..start();
    if (Platform.isAndroid) {
      _notice = DownloadNotice(context.read<OfflineStore>())..start();
      _widgets = HomeWidgetsSync(context.read<PlayerController>())..start();
      _widgetClicks = HomeWidget.widgetClicked.listen(_widgetClick);
      HomeWidget.initiallyLaunchedFromHomeWidget().then((u) {
        if (u != null) WidgetsBinding.instance.addPostFrameCallback((_) => _widgetClick(u));
      });
      if (!context.read<Settings>().askedBackground) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (mounted) await askBackgroundSetup(context);
        });
      }
    }
    if (appUpdatesSupported && context.read<Settings>().checkUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (mounted) await checkForAppUpdate(context);
      });
    }
  }

  /// The shortcuts that work from anywhere in Windows.
  Future<void> _globalHotkey(GlobalAction a) async {
    if (!mounted) return;
    final p = context.read<PlayerController>();
    switch (a) {
      case GlobalAction.playPause:
        await p.toggle();
      case GlobalAction.next:
        await p.next();
      case GlobalAction.previous:
        await p.previous();
      case GlobalAction.volumeUp:
        await p.setVolume((p.volume + 0.05).clamp(0.0, 1.0));
      case GlobalAction.volumeDown:
        await p.setVolume((p.volume - 0.05).clamp(0.0, 1.0));
      case GlobalAction.like:
        final s = p.current;
        if (s == null) {
          await notify('Nothing is playing', 'Start a song, then press the like shortcut again.');
          return;
        }
        final lib = context.read<Library>();
        final was = lib.isLiked(s);
        try {
          await lib.toggleLike(s);
          await notify(was ? 'Removed from liked songs' : 'Added to liked songs', '${s.title} · ${s.artist}');
        } catch (e) {
          await notify('Could not update liked songs', '$e');
        }
    }
  }

  void _hotkey(HotkeyAction a) {
    if (!mounted) return;
    final p = context.read<PlayerController>();
    switch (a) {
      case HotkeyAction.playPause:
        p.toggle();
      case HotkeyAction.next:
        p.next();
      case HotkeyAction.previous:
        p.previous();
      case HotkeyAction.seekForward:
      case HotkeyAction.seekBack:
        final total = p.player.duration ?? Duration(seconds: p.current?.duration ?? 0);
        var to = p.player.position + Duration(seconds: a == HotkeyAction.seekForward ? 10 : -10);
        if (to < Duration.zero) to = Duration.zero;
        if (total > Duration.zero && to > total) to = total;
        p.seek(to);
      case HotkeyAction.volumeUp:
        p.setVolume((p.volume + 0.05).clamp(0.0, 1.0));
      case HotkeyAction.volumeDown:
        p.setVolume((p.volume - 0.05).clamp(0.0, 1.0));
      case HotkeyAction.mute:
        p.setVolume(p.volume == 0 ? 0.7 : 0);
      case HotkeyAction.shuffle:
        p.toggleShuffle();
      case HotkeyAction.repeat:
        p.cycleLoop();
      case HotkeyAction.like:
        final s = p.current;
        if (s != null) likeWithToast(context, s);
      case HotkeyAction.miniPlayer:
        desktopWindow.toggleMini();
      case HotkeyAction.nowPlaying:
        if (p.current != null) openNowPlaying(context);
      case HotkeyAction.search:
        goToId('search');
    }
  }

  @override
  void dispose() {
    _notice?.dispose();
    _widgets?.dispose();
    _widgetClicks?.cancel();
    _hotkeys?.stop();
    unawaited(_globalHotkeys?.stop() ?? Future<void>.value());
    errors?.cancel();
    super.dispose();
  }

  List<TabSpec> _tabs = Capabilities.generic.tabs;

  /// Bumped when the visible page or the tab list changes, so the page inside the side-bar navigator redraws.
  final ValueNotifier<int> _rev = ValueNotifier<int>(0);

  // Android back button: tabs visited, most recent last. Back goes to the previous tab, then Home, then asks to press again to leave.
  final List<int> _history = [];
  DateTime? _lastBack;

  void _back() {
    if (_history.isNotEmpty) {
      _go(_history.removeLast());
    } else if (tab != 0) {
      _go(0);
    } else {
      final now = DateTime.now();
      if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
        SystemNavigator.pop();
      } else {
        _lastBack = now;
        context.toast('Press back again to leave');
      }
    }
  }

  void _go(int i) {
    setState(() => tab = i);
    _rev.value++;
    shellNavigator.currentState?.popUntil((r) => r.isFirst);
  }

  void goTo(int i) {
    if (i != tab) {
      _history.add(tab);
      if (_history.length > 20) _history.removeAt(0);
    }
    setState(() => tab = i);
    _rev.value++;
    // going to a tab (or tapping the open one again) returns to that tab's own page
    shellNavigator.currentState?.popUntil((r) => r.isFirst);
  }

  /// A tap on a home screen widget's shortcut (selfstream://widget/<what>).
  Future<void> _widgetClick(Uri? uri) async {
    if (uri == null || !mounted) return;
    final what = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.host;
    switch (what) {
      case 'play':
        await _widgets?.play(uri.queryParameters['pl'] ?? '', int.tryParse(uri.queryParameters['i'] ?? '') ?? 0);
        // started from the home screen: go back to it, the music keeps playing
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await SystemNavigator.pop();
      case 'now-playing':
        if (context.read<PlayerController>().current != null) openNowPlaying(context);
    }
  }

  /// Switch to a tab by the id the server gave it.
  void goToId(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i >= 0) goTo(i);
  }

  Widget _page(TabSpec t) {
    switch (t.kind) {
      case 'search':
        return const SearchScreen();
      case 'library':
        return const LibraryScreen();
      case 'nativehome':
        return ServerScreen(key: ValueKey('page-${t.id}'), screenId: t.id, title: t.title, onOpenTab: goToId, loader: nativeHome);
      default:
        return ServerScreen(key: ValueKey('page-${t.id}-${t.screen}'), screenId: t.screen, title: t.title, onOpenTab: goToId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return _full(context);
    // on a computer the window can shrink to a small player; the app keeps running underneath
    return ListenableBuilder(
      listenable: desktopWindow,
      builder: (context, _) => desktopWindow.mini ? const MiniWindow() : _full(context),
    );
  }

  Widget _full(BuildContext context) {
    final caps = context.watch<CapsHolder>();
    if (!caps.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!identical(_tabs, caps.value.tabs)) {
      _tabs = caps.value.tabs;
      WidgetsBinding.instance.addPostFrameCallback((_) => _rev.value++);
    }
    if (tab > _tabs.length) tab = 0; // the last page is Settings, after the server's tabs
    final items = [
      for (final t in _tabs) (tabIconsFor(t.icon).$1, tabIconsFor(t.icon).$2, t.title),
      (Icons.settings_outlined, Icons.settings, 'Settings'),
    ];
    final api = context.read<Api>();
    final banner = StreamBuilder<bool>(
      stream: api.offlineChanges,
      initialData: api.offline,
      builder: (_, snap) => (snap.data ?? false)
          ? Container(
              width: double.infinity,
              color: kCard,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SafeArea(
                bottom: false,
                child: Row(children: [
                  Icon(Icons.cloud_off, size: 16, color: kMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Offline or server unreachable: showing saved pages. Downloaded songs still play. Reconnects by itself.', style: TextStyle(color: kMuted, fontSize: 12))),
                ]),
              ),
            )
          : const SizedBox.shrink(),
    );
    Widget bodyNow() => Column(children: [banner, Expanded(child: IndexedStack(index: tab, children: [for (final t in _tabs) _page(t), const SettingsScreen(embedded: true)]))]);
    final body = bodyNow();
    // on a wide screen pages opened from a tab open beside the side bar, not over it
    final sideBody = Navigator(
      key: shellNavigator,
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => ValueListenableBuilder<int>(valueListenable: _rev, builder: (_, __, ___) => bodyNow())),
    );
    final page = LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 800;
      if (wide) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: tab,
              onDestinationSelected: goTo,
              labelType: NavigationRailLabelType.all,
              backgroundColor: kNav,
              trailing: !isDesktop
                  ? null
                  : Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ListenableBuilder(
                          listenable: desktopWindow,
                          builder: (context, _) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: desktopWindow.pinned ? 'Unpin from top' : 'Keep on top',
                                icon: Icon(desktopWindow.pinned ? Icons.push_pin : Icons.push_pin_outlined, color: desktopWindow.pinned ? kAccent : kMuted),
                                onPressed: desktopWindow.togglePin,
                              ),
                              IconButton(
                                tooltip: 'Mini player',
                                icon: Icon(Icons.picture_in_picture_alt_outlined, color: kMuted),
                                onPressed: desktopWindow.toggleMini,
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
              destinations: [
                for (final i in items) NavigationRailDestination(icon: Icon(i.$1), selectedIcon: Icon(i.$2), label: Text(i.$3)),
              ],
            ),
            Expanded(child: sideBody),
          ]),
          bottomNavigationBar: const MiniPlayer(),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: goTo,
            destinations: [
              for (final i in items) NavigationDestination(icon: Icon(i.$1), selectedIcon: Icon(i.$2), label: i.$3),
            ],
          ),
        ]),
      );
    });
    if (!Platform.isAndroid) return page;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: page,
    );
  }
}
