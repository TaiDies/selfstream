import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'library.dart';
import '../platform/platform.dart';
import 'audio_handler.dart';
import 'offline.dart';
import 'queue_cache.dart';
import 'settings.dart';

/// Playback, the queue, listening reports, sleep timer and "continue where you left off" across devices.
class PlayerController extends ChangeNotifier {
  PlayerController(this.api, this.library, this.offline, this.settings) {
    _subs.add(player.currentIndexStream.listen(_onIndex));
    _subs.add(player.playerStateStream.listen(_onState));
    _subs.add(player.positionStream.listen(_onPosition));
    _subs.add(player.playbackEventStream.listen((_) {}, onError: _onError));
    _subs.add(player.shuffleModeEnabledStream.listen((_) => notifyListeners()));
    _subs.add(player.loopModeStream.listen((_) => notifyListeners()));
    _subs.add(player.speedStream.listen((_) => notifyListeners()));
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkStall());
    if (!isDesktop) SelfstreamAudio.handler?.attach(this);
    if (isDesktop) {
      player.setVolume(settings.volume);
      _subs.add(player.volumeStream.listen((_) => notifyListeners()));
    }
  }

  double get volume => player.volume;
  Future<void> setVolume(double v) {
    settings.volume = v;
    return player.setVolume(v.clamp(0.0, 1.0));
  }

  final Api api;
  final Library library;
  final OfflineStore offline;
  final Settings settings;
  late final QueueCache _cache = QueueCache(api: api, settings: settings);
  bool _swapping = false;

  /// Call when playback is paused on purpose (button, notification, sleep timer).
  void markUserPause() => _userPausedAt = DateTime.now();
  bool _wantPlaying = false;
  DateTime _changedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _userPausedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Does the connected server offer this feature? (set by the session once it knows)
  bool Function(String) has = (_) => false;
  final AudioPlayer player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subs = [];
  final StreamController<String> _errors = StreamController<String>.broadcast();

  Stream<String> get errors => _errors.stream;
  Stream<Duration> get positionStream => player.positionStream;

  List<Song> queue = [];
  int index = -1;
  ConcatenatingAudioSource? _source;
  bool _disposed = false;

  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get playing => player.playing;
  bool get shuffle => player.shuffleModeEnabled;
  LoopMode get loop => player.loopMode;
  double get speed => player.speed;
  bool get hasQueue => queue.isNotEmpty;

  // ------------------------------------------------------------ building
  // Covers as files on this device: the notification, lock screen and Android Auto load these
  // directly instead of fetching a signed server URL themselves.
  final Map<String, Uri> _coverFiles = {};

  Future<void> _warmCovers(Iterable<Song> songs) async {
    if (isDesktop) return;
    final ids = <String>{for (final s in songs) s.coverArt}..removeWhere((i) => i.isEmpty || _coverFiles.containsKey(i));
    for (final id in ids.toList()) {
      final saved = offline.coverFor(id); // saved with the downloaded song: works without a connection
      if (saved != null) _coverFiles[id] = Uri.file(saved.path);
    }
    ids.removeWhere(_coverFiles.containsKey);
    final list = ids.toList();
    Future<void> one(String id) async {
      try {
        final f = await DefaultCacheManager().getSingleFile(api.coverUri(id, size: 512).toString(), key: api.coverKey(id, 512));
        _coverFiles[id] = Uri.file(f.path);
      } catch (_) {}
    }

    Future<void> all() async {
      for (var i = 0; i < list.length; i += 8) {
        await Future.wait(list.skip(i).take(8).map(one));
      }
    }

    await all().timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// The cover for the notification and lock screen: a file on this device when there is one.
  Uri artFor(Song s) => _coverFiles[s.coverArt] ?? api.coverUri(s.coverArt, size: 512);

  /// The cover file path of the current song, for home screen widgets.
  String? coverPathFor(Song s) => _coverFiles[s.coverArt]?.toFilePath();

  /// Like or unlike the current song (the notification's heart button, widgets).
  Future<void> likeCurrent() async {
    final s = current;
    if (s == null) return;
    try {
      await library.toggleLike(s);
    } catch (_) {}
  }

  AudioSource _sourceFor(Song s) {
    final path = offline.pathForSong(s) ?? _cache.pathFor(s);
    final uri = path != null ? Uri.file(path) : api.streamUri(s.id, maxBitRate: settings.maxBitRate);
    return AudioSource.uri(uri);
  }

  // ------------------------------------------------------------ playing
  Future<void> playSongs(List<Song> songs, {int start = 0, bool shuffle = false, bool checked = false}) async {
    if (songs.isEmpty) return;
    if (api.offline && !checked) {
      // no connection: only what is saved on this device can play
      final picked = songs[start.clamp(0, songs.length - 1)];
      final playable = songs.where(offline.hasSong).toList();
      if (playable.isEmpty) {
        _errors.add('Offline: none of these songs are saved on this device.');
        return;
      }
      if (!offline.hasSong(picked)) _errors.add('Offline: skipping songs that are not saved on this device.');
      final at = playable.indexOf(picked);
      return playSongs(playable, start: at < 0 ? 0 : at, shuffle: shuffle, checked: true);
    }
    await _endTrack();
    _wantPlaying = true; // you asked for playback: if it does not start by itself the watchdog gets it going
    _changedAt = DateTime.now();
    _userPausedAt = DateTime.fromMillisecondsSinceEpoch(0);
    queue = List<Song>.of(songs);
    var first = start.clamp(0, queue.length - 1);
    if (shuffle) first = Random().nextInt(queue.length);
    index = first;
    await _warmCovers(queue);
    _source = ConcatenatingAudioSource(children: queue.map(_sourceFor).toList());
    notifyListeners();
    try {
      await player.setShuffleModeEnabled(shuffle);
      await player.setAudioSource(_source!, initialIndex: first, initialPosition: Duration.zero);
      if (shuffle) await _reshuffle();
      unawaited(player.play());
    } catch (e) {
      _errors.add('Could not start playback: ${_clean(e)}');
      if (player.hasNext) {
        await player.seekToNext();
        unawaited(player.play());
      }
    }
  }

  /// Deal a fresh shuffle order. The Windows audio back end shuffles by itself and does not take a custom order
  /// (it answers "not implemented"); that must never stop the song from playing.
  Future<void> _reshuffle() async {
    try {
      await player.shuffle();
    } catch (_) {}
  }

  Future<void> playSong(Song s) => playSongs([s]);

  /// Play a list from one song, keeping the shuffle and repeat settings you have on (home screen widget).
  Future<void> playFromList(List<Song> songs, int start) async {
    final wasShuffle = player.shuffleModeEnabled;
    final wasLoop = player.loopMode;
    await playSongs(songs, start: start);
    try {
      await player.setLoopMode(wasLoop);
      if (wasShuffle) {
        await player.setShuffleModeEnabled(true);
        await _reshuffle();
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    if (player.playing) {
      _userPausedAt = DateTime.now();
      await player.pause();
    } else {
      unawaited(player.play());
    }
    notifyListeners();
  }

  Future<void> next() => player.seekToNext();

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 4) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration d) => player.seek(d);
  Future<void> jumpTo(int i) => player.seek(Duration.zero, index: i);

  Future<void> toggleShuffle() async {
    await player.setShuffleModeEnabled(!player.shuffleModeEnabled);
    if (player.shuffleModeEnabled) await _reshuffle();
    _warmUpcoming();
    _scheduleSave();
  }

  Future<void> cycleLoop() async {
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    _scheduleSave();
  }

  Future<void> setSpeed(double v) => player.setSpeed(v);

  // --------------------------------------------------------------- queue
  Future<void> addToQueue(Song s) async {
    if (queue.isEmpty || _source == null) return playSongs([s]);
    queue.add(s);
    await _warmCovers([s]);
    await _source!.add(_sourceFor(s));
    _warmUpcoming();
    notifyListeners();
    _scheduleSave();
  }

  Future<void> playNext(Song s) async {
    if (queue.isEmpty || _source == null) return playSongs([s]);
    final at = (index + 1).clamp(0, queue.length);
    queue.insert(at, s);
    await _warmCovers([s]);
    await _source!.insert(at, _sourceFor(s));
    _warmUpcoming();
    notifyListeners();
    _scheduleSave();
  }

  Future<void> addAllToQueue(List<Song> songs) async {
    for (final s in songs) {
      await addToQueue(s);
    }
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= queue.length || _source == null) return;
    queue.removeAt(i);
    await _source!.removeAt(i);
    _warmUpcoming();
    if (queue.isEmpty) {
      index = -1;
      await player.stop();
    }
    notifyListeners();
    _scheduleSave();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (_source == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final s = queue.removeAt(oldIndex);
    queue.insert(newIndex, s);
    await _source!.move(oldIndex, newIndex);
    _warmUpcoming();
    notifyListeners();
    _scheduleSave();
  }

  Future<void> clearQueue() async {
    await _endTrack();
    await player.stop();
    queue = [];
    index = -1;
    _source = null;
    notifyListeners();
    _scheduleSave();
  }

  // -------------------------------------------------------- sleep timer
  Timer? _sleepTimer;
  Duration? sleepLeft;
  bool sleepAtTrackEnd = false;
  bool get sleepActive => sleepLeft != null || sleepAtTrackEnd;

  void setSleep(Duration? d, {bool atTrackEnd = false}) {
    _sleepTimer?.cancel();
    sleepLeft = d;
    sleepAtTrackEnd = atTrackEnd;
    if (d != null) {
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        final left = (sleepLeft ?? Duration.zero) - const Duration(seconds: 1);
        if (left <= Duration.zero) {
          t.cancel();
          sleepLeft = null;
          player.pause();
        } else {
          sleepLeft = left;
        }
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // ----------------------------------------------------------- listening
  Song? _tSong;
  double _tSeconds = 0;
  double _tStart = 0;
  Duration _lastPos = Duration.zero;
  bool _tSentHalf = false;
  bool _flushing = false;

  void _beginTrack(Song? s) {
    _tSong = s;
    _tSeconds = 0;
    _tSentHalf = false;
    _tStart = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _lastPos = Duration.zero;
  }

  void _onPosition(Duration p) {
    if (_warmPending) _maybeStartWarming();
    final s = _tSong;
    if (s == null) return;
    if (player.playing) {
      final d = p - _lastPos;
      if (d.inMilliseconds > 0 && d.inMilliseconds < 3000) _tSeconds += d.inMilliseconds / 1000.0;
    }
    _lastPos = p;
    if (!_tSentHalf && _tSeconds >= 30) {
      _tSentHalf = true;
      _report(s, final_: false);
      if (!s.isCloud) api.scrobble(s.id).catchError((Object _) {});
    }
    _maybeSave(p);
  }

  Future<void> _endTrack() async {
    final s = _tSong;
    if (s != null && _tSeconds >= 1) await _report(s, final_: true);
    _tSong = null;
    _tSeconds = 0;
  }

  Future<void> _report(Song s, {required bool final_}) async {
    if (!settings.trackListening || !has('history')) return;
    final play = <String, dynamic>{
      'song': s.toJson(),
      'seconds': double.parse(_tSeconds.toStringAsFixed(1)),
      'duration': s.duration,
      'ts': _tStart,
    };
    try {
      final pending = settings.pendingPlays;
      if (pending.isNotEmpty && !_flushing) {
        _flushing = true;
        try {
          await api.reportPlays(pending);
          settings.pendingPlays = [];
        } finally {
          _flushing = false;
        }
      }
      await api.reportPlay(play);
    } catch (_) {
      if (final_) settings.pendingPlays = [...settings.pendingPlays, play];
    }
  }

  // ------------------------------------------------------------- events
  void _onIndex(int? i) {
    if (_swapping) return; // swapping a queued song for its saved file moves the index for a moment
    final newIndex = i ?? -1;
    if (newIndex == index && _tSong != null) return;
    final wasEnd = sleepAtTrackEnd;
    unawaited(_endTrack().then((_) {
      index = newIndex;
      _changedAt = DateTime.now();
      _beginTrack(current);
      _warmUpcoming();
      notifyListeners();
      _scheduleSave();
    }));
    if (wasEnd) {
      sleepAtTrackEnd = false;
      markUserPause();
      player.pause();
      player.seek(Duration.zero);
    }
  }

  // ------------------------------------------------------ stall recovery
  // A streamed song sometimes sits there "playing" without sound until you pause and resume it. This does that for you.
  Timer? _watchdog;
  DateTime? _stuckSince;
  Duration _stallPos = Duration.zero;
  String? _recoverySong;
  int _recoveries = 0;
  bool _recovering = false;

  void _checkStall() {
    if (_disposed || _recovering) return;
    final st = player.processingState;
    final sinceChange = DateTime.now().difference(_changedAt);
    // the next song was loaded but playback dropped to "paused" on its own: carry on playing it
    if (_wantPlaying && !player.playing && sinceChange < const Duration(seconds: 8) && _userPausedAt.isBefore(_changedAt) && st != ProcessingState.completed && index >= 0) {
      Api.noteError('playback stopped at a song change, resumed');
      unawaited(player.play());
      return;
    }
    // the back end gave up on the song (it reports "idle") although you want it playing: load it again
    if (st == ProcessingState.idle && _wantPlaying && index >= 0 && queue.isNotEmpty && sinceChange > const Duration(seconds: 2) && _userPausedAt.isBefore(_changedAt)) {
      _stuckSince ??= DateTime.now();
      if (DateTime.now().difference(_stuckSince!) > const Duration(seconds: 2)) {
        _stuckSince = DateTime.now();
        unawaited(_recover(stage: 3));
      }
      return;
    }
    final waiting = st == ProcessingState.loading || st == ProcessingState.buffering;
    final frozen = st == ProcessingState.ready && player.position == _stallPos;
    _stallPos = player.position;
    if (!player.playing || st == ProcessingState.idle || st == ProcessingState.completed || !(waiting || frozen)) {
      _stuckSince = null;
      if (st == ProcessingState.ready && player.playing && !frozen) {
        _recoveries = 0;
        _errorRetrySong = null;
      }
      return;
    }
    _stuckSince ??= DateTime.now();
    // right after a song change a stuck player is fixed sooner than one that stalls in the middle of a song
    if (DateTime.now().difference(_stuckSince!) < (sinceChange < const Duration(seconds: 12) ? const Duration(seconds: 3) : const Duration(seconds: 8))) return;
    _stuckSince = DateTime.now();
    unawaited(_recover());
  }

  Future<void> _recover({int? stage}) async {
    final song = current;
    if (song == null || _source == null) return;
    if (_recoverySong != song.id) {
      _recoverySong = song.id;
      _recoveries = 0;
    }
    if (_recoveries >= 3) {
      if (_giveUpAt == null || DateTime.now().difference(_giveUpAt!) < const Duration(seconds: 30)) {
        _giveUpAt ??= DateTime.now();
        return; // wait a while, then run through the steps once more
      }
      _recoveries = 0;
    }
    _giveUpAt = null;
    _recoveries++;
    final step = stage ?? _recoveries;
    _recovering = true;
    Api.noteError('playback stalled on a song, recovery step $step');
    try {
      final pos = player.position;
      if (step == 1) {
        // what you do by hand: pause, a moment, play (without waiting for the back end to answer)
        unawaited(player.pause().catchError((Object _) {}));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        unawaited(player.play().catchError((Object _) {}));
      } else if (step == 2) {
        await player.seek(pos).timeout(const Duration(seconds: 4));
        unawaited(player.play().catchError((Object _) {}));
      } else {
        await player.setAudioSource(_source!, initialIndex: index, initialPosition: pos).timeout(const Duration(seconds: 15));
        unawaited(player.play().catchError((Object _) {}));
      }
    } catch (_) {
    } finally {
      _recovering = false;
    }
  }

  DateTime? _giveUpAt;

  /// The queue positions that play after the current song, in playing order (follows shuffle).
  List<int> _upcomingIndices(int n) {
    if (index < 0 || queue.isEmpty) return const [];
    List<int> order = List<int>.generate(queue.length, (i) => i);
    if (player.shuffleModeEnabled) {
      final eff = player.effectiveIndices;
      if (eff != null && eff.length == queue.length) order = eff;
    }
    final at = order.indexOf(index);
    if (at < 0) return const [];
    final out = <int>[];
    for (var k = 1; k <= n; k++) {
      var p = at + k;
      if (p >= order.length) {
        if (player.loopMode != LoopMode.all) break;
        p %= order.length;
      }
      if (order[p] != index) out.add(order[p]);
    }
    return out;
  }

  bool _warmPending = false;

  /// The next 4 songs are only fetched once the current song is really playing, so they never compete with it
  /// for the connection. A skip stops whatever was being fetched; the new current song loads first.
  void _warmUpcoming() {
    if (_disposed || index < 0) return;
    _cache.cancelAll();
    _warmPending = true;
    _maybeStartWarming();
  }

  void _maybeStartWarming() {
    if (!_warmPending || _disposed || index < 0) return;
    final loaded = player.playing && player.processingState == ProcessingState.ready && player.position > const Duration(seconds: 1);
    final local = current != null && (offline.pathForSong(current!) != null || _cache.pathFor(current!) != null);
    if (!loaded && !(local && player.processingState == ProcessingState.ready)) return;
    _warmPending = false;
    final next = [for (final i in _upcomingIndices(4)) queue[i]].where((s) => offline.pathForSong(s) == null).toList();
    final cloud = [for (final s in next) if (s.isCloud && _cache.pathFor(s) == null) s.id];
    if (cloud.isNotEmpty) unawaited(api.prefetch(cloud));
    if (api.offline) return;
    final keep = <String>{if (current != null) current!.id};
    unawaited(_cache.fill(next, keep: keep, onReady: _swapIn));
  }

  /// A queued song has been saved: let the player use the file instead of the stream.
  Future<void> _swapIn(Song s, String path) async {
    final src = _source;
    if (src == null || _disposed) return;
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].id != s.id || i == index) continue;
      _swapping = true;
      try {
        await src.removeAt(i);
        await src.insert(i, AudioSource.uri(Uri.file(path)));
      } catch (_) {
        // the song then simply plays from the stream
      } finally {
        _swapping = false;
      }
    }
  }

  void _onState(PlayerState state) {
    if (state.playing) {
      _wantPlaying = true;
    } else if (!_userPausedAt.isBefore(_changedAt)) {
      _wantPlaying = false; // paused by you (or the sleep timer), not dropped by a song change
    }
    if (state.playing && _tSong == null && current != null) _beginTrack(current);
    if (state.processingState == ProcessingState.completed) {
      unawaited(_endTrack());
    }
    notifyListeners();
  }

  String? _errorRetrySong;

  void _onError(Object error, StackTrace st) {
    Api.noteError('player error: ${_clean(error)}');
    final song = current;
    // a song that fails to load often works on the second try: load it again once before giving up on it
    if (song != null && _source != null && _errorRetrySong != song.id) {
      _errorRetrySong = song.id;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 800)).then((_) {
        if (!_disposed && current?.id == song.id) return _recover(stage: 3);
      }));
      return;
    }
    _errors.add('Playback problem: ${_clean(error)}');
    if (player.hasNext) {
      player.seekToNext();
    }
  }

  String _clean(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}...' : s;
  }

  // -------------------------------------------------- sync across devices
  Timer? _saveTimer;
  DateTime _lastPosSave = DateTime.fromMillisecondsSinceEpoch(0);

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 4), _save);
  }

  void _maybeSave(Duration p) {
    if (player.playing && DateTime.now().difference(_lastPosSave) > const Duration(seconds: 30)) {
      _lastPosSave = DateTime.now();
      _save();
    }
  }

  static const _localKey = 'last_queue';

  Map<String, dynamic> _snapshot() => {
        'songs': queue.take(300).map((s) => s.toJson()).toList(),
        'index': queue.length > 300 ? min(index, 299) : index,
        'positionMs': player.position.inMilliseconds,
        'shuffle': shuffle,
        'loop': loop.index,
      };

  Future<void> _save() async {
    if (_disposed || queue.isEmpty) return;
    final snap = _snapshot();
    try {
      // kept on this device too, so Android Auto can carry on where you stopped even without the server's help
      (await SharedPreferences.getInstance()).setString(_localKey, jsonEncode(snap));
    } catch (_) {}
    try {
      if (has('state')) await api.putState('queue', snap);
    } catch (_) {}
  }

  /// Load the queue saved by the last device, paused, so you can continue.
  Future<void> restore() async {
    if (queue.isNotEmpty) return;
    try {
      Object? v;
      if (has('state')) {
        try {
          v = await api.getState('queue');
        } catch (_) {}
      }
      if (v is! Map) {
        final raw = (await SharedPreferences.getInstance()).getString(_localKey);
        v = raw == null ? null : jsonDecode(raw);
      }
      if (v is! Map) return;
      final songs = songsFrom(v['songs']);
      if (songs.isEmpty || queue.isNotEmpty) return;
      final i = ((v['index'] as num?)?.toInt() ?? 0).clamp(0, songs.length - 1);
      queue = songs;
      index = i;
      await _warmCovers(songs);
      _source = ConcatenatingAudioSource(children: songs.map(_sourceFor).toList());
      await player.setAudioSource(_source!,
          initialIndex: i, initialPosition: Duration(milliseconds: (v['positionMs'] as num?)?.toInt() ?? 0));
      final loopIndex = ((v['loop'] as num?)?.toInt() ?? 0).clamp(0, LoopMode.values.length - 1);
      await player.setLoopMode(LoopMode.values[loopIndex]);
      await player.setShuffleModeEnabled(v['shuffle'] == true);
      _beginTrack(null); // do not count the restored track as a listen until it plays
      notifyListeners();
      if (!isDesktop) SelfstreamAudio.handler?.restored(this);
    } catch (_) {
      // nothing to restore, or the saved song is gone
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!isDesktop) SelfstreamAudio.handler?.detach(this);
    _saveTimer?.cancel();
    _sleepTimer?.cancel();
    _watchdog?.cancel();
    _cache.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _errors.close();
    player.dispose();
    super.dispose();
  }
}
