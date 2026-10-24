import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'auto_cover.dart';
import 'player.dart';

/// Android: the system media notification, lock screen, headset buttons and Android Auto.
/// It mirrors the app's [PlayerController] and adds a Like button next to previous / play / next.
class SelfstreamAudio {
  static SelfstreamHandler? handler;

  /// Set by the home screen widgets: play a song of a widget playlist.
  static Future<void> Function(String listId, int index)? onWidgetPlay;

  static Future<void> init() async {
    handler = await AudioService.init(
      builder: () => SelfstreamHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.selfstream.audio',
        androidNotificationChannelName: 'Selfstream playback',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'drawable/ic_stat_selfstream',
        // Android Auto drops cover bitmaps that are too big for the media session, so hand it a smaller one.
        artDownscaleWidth: 320,
        artDownscaleHeight: 320,
      ),
    );
    await handler?.loadLast();
  }
}

class SelfstreamHandler extends BaseAudioHandler with SeekHandler {
  PlayerController? _c;
  final List<StreamSubscription<Object?>> _subs = [];
  String _itemKey = '';
  String _queueKey = '';

  bool _playWhenReady = false;
  Timer? _readyTimer;

  /// Show the last played song straight away (before the app has signed in and restored its queue), so Android Auto
  /// sees Selfstream as the app to resume instead of handing the screen to another player.
  Future<void> loadLast() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString('last_queue');
      if (raw == null) return;
      final v = jsonDecode(raw);
      if (v is! Map) return;
      final songs = songsFrom(v['songs']);
      if (songs.isEmpty) return;
      final s = songs[((v['index'] as num?)?.toInt() ?? 0).clamp(0, songs.length - 1)];
      mediaItem.add(MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        artUri: s.coverArt.isNotEmpty ? AutoCovers.uriFor(s.coverArt) : null,
        duration: s.duration > 0 ? Duration(seconds: s.duration) : null,
      ));
      playbackState.add(PlaybackState(
        controls: [MediaControl.skipToPrevious, MediaControl.play, MediaControl.skipToNext],
        processingState: AudioProcessingState.ready,
        playing: false,
      ));
    } catch (_) {}
  }

  /// Something (Android Auto, a headset) asked to play before the queue was loaded: play as soon as it is.
  void _playAfterRestore() {
    _playWhenReady = true;
    _readyTimer?.cancel();
    _readyTimer = Timer(const Duration(seconds: 90), () => _playWhenReady = false);
  }

  /// The player has loaded the saved queue.
  void restored(PlayerController c) {
    if (!_playWhenReady || c.queue.isEmpty) return;
    _playWhenReady = false;
    _readyTimer?.cancel();
    unawaited(c.player.play());
  }

  void attach(PlayerController c) {
    detach();
    _c = c;
    _subs.add(c.player.playbackEventStream.listen((_) => _pushState(), onError: (Object _) {}));
    c.addListener(_pushAll);
    c.library.addListener(_pushState);
    _pushAll();
  }

  void detach([PlayerController? only]) {
    final c = _c;
    if (c == null || (only != null && !identical(only, c))) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    c.removeListener(_pushAll);
    c.library.removeListener(_pushState);
    _c = null;
    _itemKey = '';
    _queueKey = '';
    queue.add(const []);
    mediaItem.add(null);
    playbackState.add(PlaybackState());
  }

  /// Android Auto can only read content:// covers, so those come from the app's CoverProvider.
  Uri _art(PlayerController c, Song s) =>
      Platform.isAndroid && s.coverArt.isNotEmpty ? AutoCovers.uriFor(s.coverArt) : c.artFor(s);

  MediaItem _item(PlayerController c, Song s) => MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        artUri: _art(c, s),
        duration: s.duration > 0 ? Duration(seconds: s.duration) : null,
      );

  Future<void> _pushAll() async {
    final c = _c;
    if (c == null) return;
    try {
      final qKey = '${c.queue.length}|${c.queue.isEmpty ? '' : c.queue.first.id}|${c.queue.isEmpty ? '' : c.queue.last.id}';
      if (qKey != _queueKey) {
        _queueKey = qKey;
        queue.add([for (final s in c.queue) _item(c, s)]);
      }
      final s = c.current;
      final iKey = s == null ? '' : '${s.id}|${c.artFor(s)}';
      if (iKey != _itemKey) {
        _itemKey = iKey;
        if (s != null) await AutoCovers.ensure(s.coverArt, c.artFor(s));
        if (_c != c || c.current?.id != s?.id) return; // moved on while the cover was loading
        mediaItem.add(s == null ? null : _item(c, s));
      }
      _pushState();
    } catch (_) {}
  }

  void _pushState() {
    final c = _c;
    if (c == null) return;
    if (c.queue.isEmpty && mediaItem.value != null) return; // keep showing the last song until the queue is loaded
    try {
      final p = c.player;
      final song = c.current;
      final liked = song != null && c.library.isLiked(song);
      playbackState.add(PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (p.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.custom(
            androidIcon: liked ? 'drawable/ic_liked' : 'drawable/ic_like',
            label: liked ? 'Remove from liked songs' : 'Like',
            name: 'like',
          ),
        ],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 2],
        // "idle" makes Android drop the media session (and Android Auto hands over to another app), so while there
        // is a queue we report "loading" instead, e.g. in the moment between two songs.
        processingState: (c.queue.isEmpty && p.processingState == ProcessingState.idle)
            ? AudioProcessingState.idle
            : const {
          ProcessingState.idle: AudioProcessingState.loading,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[p.processingState]!,
        playing: p.playing,
        updatePosition: p.position,
        bufferedPosition: p.bufferedPosition,
        speed: p.speed,
        queueIndex: c.index >= 0 ? c.index : null,
      ));
    } catch (_) {}
  }

  @override
  Future<void> play() async {
    final c = _c;
    if (c == null || c.queue.isEmpty) {
      _playAfterRestore();
      return;
    }
    unawaited(c.player.play());
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> prepareFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {}

  @override
  Future<void> pause() async {
    _c?.markUserPause();
    await _c?.player.pause();
  }

  @override
  Future<void> stop() async {
    _c?.markUserPause();
    await _c?.player.pause();
  }

  @override
  Future<void> skipToNext() async => _c?.next();

  @override
  Future<void> skipToPrevious() async => _c?.previous();

  @override
  Future<void> seek(Duration position) async => _c?.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async => _c?.jumpTo(index);

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.recentRootId) {
      final m = mediaItem.value;
      return m == null ? const [] : [m];
    }
    return queue.value;
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final c = _c;
    if (c == null || c.queue.isEmpty) {
      _playAfterRestore();
      return;
    }
    final i = c.queue.indexWhere((s) => s.id == mediaId);
    if (i >= 0) {
      await c.jumpTo(i);
      unawaited(c.player.play());
    }
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'like':
        await _c?.likeCurrent();
      case 'shuffle':
        await _c?.toggleShuffle();
      case 'repeat':
        await _c?.cycleLoop();
      case 'playlist':
        final id = '${extras?['pl'] ?? ''}';
        final i = (extras?['i'] as num?)?.toInt() ?? 0;
        if (id.isNotEmpty) await SelfstreamAudio.onWidgetPlay?.call(id, i);
    }
    return null;
  }
}
