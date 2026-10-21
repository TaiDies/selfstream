import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/platform.dart';
import '../core/duplicates.dart';
import '../core/models.dart';
import '../state/library.dart';
import '../state/offline.dart';
import 'duplicates_screen.dart';
import 'widgets.dart';

/// A playlist stored on the server, so it is the same on every device.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId, this.name = ''});
  final String playlistId;
  final String name;
  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  PlaylistFull? pl;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.api.playlist(widget.playlistId);
      if (!mounted) return;
      setState(() {
        pl = r;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _remove(Song s) async {
    final id = s.playlistItemId;
    if (id == null) return;
    final at = pl!.songs.indexWhere((x) => x.playlistItemId == id);
    setState(() => pl!.songs.removeWhere((x) => x.playlistItemId == id));
    final api = context.api;
    final lib = context.lib;
    try {
      await api.removeFromPlaylist(widget.playlistId, id);
      await lib.refresh();
      if (mounted) context.toastUndo('Removed from playlist', () => _restore(s, at));
    } catch (e) {
      if (mounted) {
        context.toast('Could not remove: $e');
        _load();
      }
    }
  }

  /// Undo: put the song back where it was.
  Future<void> _restore(Song s, int at) async {
    final api = context.api;
    final lib = context.lib;
    await api.addToPlaylist(widget.playlistId, [s]);
    final r = await api.playlist(widget.playlistId);
    final ids = [for (final x in r.songs) if (x.playlistItemId != null) x.playlistItemId!];
    if (ids.length > 1 && at >= 0 && at < ids.length - 1) {
      final added = ids.removeLast();
      ids.insert(at, added);
      try {
        await api.reorderPlaylist(widget.playlistId, ids);
      } catch (_) {}
    }
    await lib.refresh();
    if (mounted) _load();
  }

  Future<void> _reorder(int from, int to) async {
    final list = pl!.songs;
    if (to > from) to -= 1;
    setState(() => list.insert(to, list.removeAt(from)));
    try {
      await context.api.reorderPlaylist(widget.playlistId, [for (final s in list) if (s.playlistItemId != null) s.playlistItemId!]);
    } catch (e) {
      if (mounted) {
        context.toast('Could not reorder: $e');
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final info = pl?.info;
    final songs = pl?.songs ?? [];
    Follow? follow;
    for (final f in lib.follows) {
      if (f.playlistId == widget.playlistId) follow = f;
    }
    return PageFrame(
      title: info?.name ?? widget.name,
      actions: [
        if (info != null)
          PopupMenuButton<String>(
            onSelected: (v) async {
              final navigator = Navigator.of(context);
              if (v == 'rename') {
                final name = await askText(context, 'Rename playlist', 'Name', initial: info.name);
                if (name == null || name.trim().isEmpty || !context.mounted) return;
                await lib.renamePlaylist(info, name.trim());
                _load();
              } else if (v == 'delete') {
                final ok = await confirm(context, 'Delete "${info.name}"?', 'The songs stay in your library.', ok: 'Delete');
                if (!ok) return;
                await lib.deletePlaylist(info);
                navigator.pop();
              } else if (v == 'offline') {
                if (context.mounted) context.toast('Saving ${songs.length} songs for offline');
                await context.read<OfflineStore>().downloadAll(songs);
              } else if (v == 'dupes') {
                final groups = findDuplicates(songs);
                if (groups.isEmpty) {
                  if (context.mounted) context.toast('No duplicates in this playlist');
                  return;
                }
                if (!context.mounted) return;
                final changed = await context.open<bool>(DuplicatesScreen(playlistId: widget.playlistId, groups: groups));
                if (changed == true) _load();
              } else if (v == 'queue') {
                await context.player.addAllToQueue(songs);
                if (context.mounted) context.toast('Added to queue');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'queue', child: Text('Add all to queue')),
              if (!isDesktop) const PopupMenuItem(value: 'offline', child: Text('Save all for offline')),
              const PopupMenuItem(value: 'dupes', child: Text('Remove duplicates')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
      ],
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? EmptyNote(error!, icon: Icons.error_outline)
              : ReorderableListView.builder(
                  header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(children: [
                        Cover(info?.coverArt ?? '', size: 110, radius: 10),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(info?.name ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            if ((info?.description ?? '').isNotEmpty) Text(info!.description, style: TextStyle(color: kMuted)),
                            Text('${songs.length} songs · ${fmtListening(info?.duration ?? 0)}', style: TextStyle(color: kMuted)),
                          ]),
                        ),
                      ]),
                    ),
                    if (follow != null && follow.active)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Downloading to your library: ${follow.done + follow.failed}/${follow.total}', style: TextStyle(color: kAccent, fontSize: 12)),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: follow.total == 0 ? null : follow.progress),
                        ]),
                      ),
                    if (follow != null && !follow.active && follow.failed > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text('${follow.failed} songs could not be downloaded.', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                      ),
                    PlayButtons(songs: songs),
                  ]),
                  itemCount: songs.length,
                  onReorder: _reorder,
                  itemBuilder: (_, i) {
                    final s = songs[i];
                    return Dismissible(
                      key: ValueKey('${s.playlistItemId}-${s.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(color: Colors.red.shade900, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete)),
                      onDismissed: (_) => _remove(s),
                      child: SongTile(
                        song: s,
                        onTap: () => context.player.playSongs(songs, start: i),
                        menuExtras: [SongAction(Icons.remove_circle_outline, 'Remove from this playlist', () => _remove(s))],
                      ),
                    );
                  },
                ),
    );
  }
}
