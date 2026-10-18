import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import 'player.dart';

/// Android: keeps the home screen widgets up to date with what is playing.
/// The widgets' buttons talk to the media notification's session directly (see the native side), so
/// they work with the screen locked or the app in the background.
class HomeWidgetsSync {
  HomeWidgetsSync(this.player);
  final PlayerController player;

  static const providers = [
    'dev.selfstream.widgets.NowPlayingWidget',
    'dev.selfstream.widgets.ControlsWidget',
    'dev.selfstream.widgets.CoverWidget',
  ];

  Timer? _debounce;
  String _last = '';
  bool _started = false;

  void start() {
    if (!Platform.isAndroid || _started) return;
    _started = true;
    player.addListener(_changed);
    player.library.addListener(_changed);
    _changed();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _debounce?.cancel();
    player.removeListener(_changed);
    player.library.removeListener(_changed);
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_push()));
  }

  Future<void> _push() async {
    try {
      final s = player.current;
      final title = s?.title ?? '';
      final artist = s?.artist ?? '';
      final playing = player.playing;
      final liked = s != null && player.library.isLiked(s);
      final cover = s == null ? '' : (player.coverPathFor(s) ?? '');
      final active = player.queue.isNotEmpty;
      final sig = '$title|$artist|$playing|$liked|$cover|$active';
      if (sig == _last) return;
      _last = sig;
      await HomeWidget.saveWidgetData<String>('title', title);
      await HomeWidget.saveWidgetData<String>('artist', artist);
      await HomeWidget.saveWidgetData<bool>('playing', playing);
      await HomeWidget.saveWidgetData<bool>('liked', liked);
      await HomeWidget.saveWidgetData<String>('cover', cover);
      await HomeWidget.saveWidgetData<bool>('active', active);
      for (final p in providers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: p);
      }
    } catch (_) {}
  }
}
