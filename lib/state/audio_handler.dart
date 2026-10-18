import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../core/models.dart';
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
      ),
    );
  }
}

class SelfstreamHandler extends BaseAudioHandler with SeekHandler {
  PlayerController? _c;
  final List<StreamSubscription<Object?>> _subs = [];
  String _itemKey = '';
  String _queueKey = '';

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

  MediaItem _item(PlayerController c, Song s) => MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        artUri: c.artFor(s),
        duration: s.duration > 0 ? Duration(seconds: s.duration) : null,
      );

  void _pushAll() {
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
        mediaItem.add(s == null ? null : _item(c, s));
      }
      _pushState();
    } catch (_) {}
  }

  void _pushState() {
    final c = _c;
    if (c == null) return;
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
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
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
    if (c != null) unawaited(c.player.play());
  }

  @override
  Future<void> pause() async => _c?.player.pause();

  @override
  Future<void> stop() async => _c?.player.pause();

  @override
  Future<void> skipToNext() async => _c?.next();

  @override
  Future<void> skipToPrevious() async => _c?.previous();

  @override
  Future<void> seek(Duration position) async => _c?.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async => _c?.jumpTo(index);

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async => queue.value;

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final c = _c;
    if (c == null) return;
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
