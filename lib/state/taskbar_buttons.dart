import 'dart:async';
import 'dart:io';

import 'package:windows_taskbar/windows_taskbar.dart';

import 'player.dart';

/// Windows: buttons in the preview that shows when you hover the app in the taskbar:
/// like, previous, play / pause, next.
class TaskbarButtons {
  TaskbarButtons(this.player);
  final PlayerController player;

  static bool get supported => Platform.isWindows;

  Timer? _debounce;
  StreamSubscription<Object?>? _sub;
  String _shown = '';
  bool _disposed = false;

  void start() {
    player.addListener(_changed);
    _sub = player.player.playerStateStream.listen((_) => _changed());
    _changed();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _apply);
  }

  Future<void> _apply() async {
    if (_disposed) return;
    final song = player.current;
    final playing = player.player.playing;
    final liked = song != null && player.library.isLiked(song);
    final key = '$playing|$liked';
    if (key == _shown) return;
    try {
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(liked ? 'assets/taskbar/liked.ico' : 'assets/taskbar/like.ico'),
          liked ? 'Remove from liked songs' : 'Like',
          () {
            if (player.current != null) unawaited(player.likeCurrent());
          },
        ),
        ThumbnailToolbarButton(ThumbnailToolbarAssetIcon('assets/taskbar/previous.ico'), 'Previous', () {
          if (player.current != null) unawaited(player.previous());
        }),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(playing ? 'assets/taskbar/pause.ico' : 'assets/taskbar/play.ico'),
          playing ? 'Pause' : 'Play',
          () {
            if (player.current == null) return;
            unawaited(player.toggle());
          },
        ),
        ThumbnailToolbarButton(ThumbnailToolbarAssetIcon('assets/taskbar/next.ico'), 'Next', () {
          if (player.current != null) unawaited(player.next());
        }),
      ]);
      _shown = key;
    } catch (_) {
      // the taskbar is not ready yet; the next change tries again
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _sub?.cancel();
    player.removeListener(_changed);
    if (supported) unawaited(WindowsTaskbar.resetThumbnailToolbar().catchError((Object _) {}));
  }
}
