import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../core/models.dart';
import 'audio_handler.dart';
import 'player.dart';

/// Android: keeps the home screen widgets up to date (what is playing, and your playlists with their songs).
/// The widgets' buttons talk to the media session directly (see the native side), so they work with the
/// screen locked or the app in the background.
class HomeWidgetsSync {
  HomeWidgetsSync(this.player);
  final PlayerController player;

  static const providers = [
    'dev.selfstream.widgets.ControlsWidget',
    'dev.selfstream.widgets.PlaylistsWidget',
  ];
  static const maxLists = 200;

  Timer? _debounce;
  Timer? _listDebounce;
  String _last = '';
  String _lastLists = '';
  bool _started = false;
  bool _building = false;
  final Map<String, List<Song>> _songs = {};

  void start() {
    if (!Platform.isAndroid || _started) return;
    _started = true;
    player.addListener(_changed);
    player.library.addListener(_listsChanged);
    player.library.addListener(_changed); // the heart follows likes made anywhere
    SelfstreamAudio.onWidgetPlay = play;
    _changed();
    _listsChanged(delay: const Duration(seconds: 6));
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _debounce?.cancel();
    _listDebounce?.cancel();
    player.removeListener(_changed);
    player.library.removeListener(_listsChanged);
    player.library.removeListener(_changed);
    if (SelfstreamAudio.onWidgetPlay == play) SelfstreamAudio.onWidgetPlay = null;
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_push()));
  }

  void _listsChanged({Duration delay = const Duration(seconds: 3)}) {
    _listDebounce?.cancel();
    _listDebounce = Timer(delay, () => unawaited(_pushLists()));
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
      final shuffle = player.shuffle;
      final loop = player.loop.index == 0 ? '0' : (player.loop.index == 1 ? '2' : '1'); // off, one, all -> 0, 2, 1
      final current = s?.id ?? '';
      final sig = '$title|$artist|$playing|$liked|$cover|$active|$shuffle|$loop|$current';
      if (sig == _last) return;
      _last = sig;
      await HomeWidget.saveWidgetData<String>('title', title);
      await HomeWidget.saveWidgetData<String>('artist', artist);
      await HomeWidget.saveWidgetData<bool>('playing', playing);
      await HomeWidget.saveWidgetData<bool>('liked', liked);
      await HomeWidget.saveWidgetData<String>('cover', cover);
      await HomeWidget.saveWidgetData<bool>('active', active);
      await HomeWidget.saveWidgetData<bool>('shuffle', shuffle);
      await HomeWidget.saveWidgetData<String>('loop', loop);
      await HomeWidget.saveWidgetData<String>('current', current);
      for (final p in providers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: p);
      }
    } catch (_) {}
  }

  /// Liked songs first, then your playlists, each with its songs for the playlists widget.
  Future<void> _pushLists() async {
    if (_building || !_started) return;
    _building = true;
    try {
      final lib = player.library;
      final lists = <({String id, String name, List<Song> songs})>[];
      lists.add((id: 'liked', name: 'Liked songs', songs: lib.likedSongs.toList()));
      for (final p in lib.playlists.take(maxLists)) {
        if (p.id.isEmpty) continue;
        try {
          final full = await player.api.playlist(p.id);
          lists.add((id: p.id, name: p.name, songs: full.songs));
        } catch (_) {
          final cached = _songs[p.id];
          if (cached != null) lists.add((id: p.id, name: p.name, songs: cached));
        }
        if (!_started) return;
      }
      final sig = lists.map((l) => '${l.id}:${l.name}:${l.songs.map((s) => s.id).join(',')}').join('|');
      if (sig == _lastLists) return;
      _lastLists = sig;
      for (final l in lists) {
        _songs[l.id] = l.songs;
      }
      await HomeWidget.saveWidgetData<String>('pl_names', jsonEncode([for (final l in lists) {'id': l.id, 'name': l.name, 'n': l.songs.length}]));
      for (var i = 0; i < lists.length; i++) {
        await HomeWidget.saveWidgetData<String>('pl_songs_$i', jsonEncode([for (final s in lists[i].songs) {'s': s.id, 't': s.title, 'a': s.artist, 'c': _coverFor(s)}]));
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: providers[1]);
    } catch (_) {
    } finally {
      _building = false;
    }
  }

  /// Where the widget can find a song's small cover: a saved file, or the (token-signed) address.
  String _coverFor(Song s) {
    if (s.coverArt.isEmpty) return '';
    return player.coverPathFor(s) ?? player.api.coverUri(s.coverArt, size: 96).toString();
  }

  /// A song tapped in the playlists widget (or the playlist title: index 0).
  Future<void> play(String listId, int index) async {
    try {
      var songs = listId == 'liked' ? player.library.likedSongs : (_songs[listId] ?? const <Song>[]);
      // just started from the home screen: give the library a moment to load
      for (var i = 0; i < 15 && songs.isEmpty && listId == 'liked'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        songs = player.library.likedSongs;
      }
      if (listId != 'liked' && songs.isEmpty) songs = (await player.api.playlist(listId)).songs;
      if (songs.isEmpty) return;
      await player.playFromList(songs, index.clamp(0, songs.length - 1));
    } catch (_) {}
  }
}
