import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/platform.dart';
import '../core/models.dart';
import '../state/caps_holder.dart';
import '../state/library.dart';
import '../state/offline.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';
import 'download_controls.dart';
import 'widgets.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final caps = context.watch<CapsHolder>();
    // (label, page): what the connected server cannot do simply has no tab
    final tabs = <(String, Widget)>[
      if (caps.has('playlists')) ('Playlists', const _PlaylistsTab()),
      ('Liked', const _LikedTab()),
      // with follows, these list what you follow; without, what the server has
      ('Albums', caps.has('follows') ? const _FollowedTab('album') : const _AlbumsTab()),
      ('Artists', caps.has('follows') ? const _FollowedTab('artist') : const _ArtistsTab()),
      if (!isDesktop) ('Offline', const _OfflineTab()),
    ];
    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$1)]),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await askText(context, 'New playlist', 'Name');
          if (name == null || name.trim().isEmpty || !context.mounted) return;
          try {
            final p = await lib.createPlaylist(name.trim());
            if (context.mounted) context.open(PlaylistScreen(playlistId: p.id, name: p.name));
          } catch (e) {
            if (context.mounted) context.toast('$e');
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: RefreshIndicator(
        onRefresh: lib.refresh,
        child: lib.playlists.isEmpty
            ? ListView(children: const [SizedBox(height: 80), EmptyNote('No playlists yet.\nCreate one here, or add songs from any song menu.\nPlaylists live on your server, so every device sees them.', icon: Icons.queue_music)])
            : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                for (final p in lib.playlists)
                  ListTile(
                    leading: Cover(p.coverArt, size: 52),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p.songCount} songs${p.isFollow ? ' · followed' : ''}', style: TextStyle(color: kMuted)),
                    onTap: () => context.open(PlaylistScreen(playlistId: p.id, name: p.name)),
                  ),
              ]),
      ),
    );
  }
}

/// The albums or artists you follow (each one is kept up to date as its own playlist).
class _FollowedTab extends StatelessWidget {
  const _FollowedTab(this.kind);
  final String kind;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final items = [for (final f in lib.follows) if (f.kind == kind) f];
    final artist = kind == 'artist';
    if (items.isEmpty) {
      return EmptyNote(artist ? 'Follow an artist and it shows up here.' : 'Follow an album and it shows up here.', icon: artist ? Icons.person_outline : Icons.album_outlined);
    }
    String coverOf(Follow f) {
      for (final p in lib.playlists) {
        if (p.id == f.playlistId) return p.coverArt;
      }
      return '';
    }

    return RefreshIndicator(
      onRefresh: lib.refresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, childAspectRatio: 0.78),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final f = items[i];
          return GestureDetector(
            onLongPress: () async {
              final remove = await confirm(context, 'Unfollow "${f.name}"?', 'Its playlist stays. It just stops updating.', ok: 'Unfollow');
              if (remove && context.mounted) await lib.unfollow(f);
            },
            child: CardTile(
              coverId: coverOf(f),
              title: f.name.isEmpty ? f.remoteId : f.name,
              subtitle: f.status == 'error' ? 'Something went wrong' : (f.active ? 'Updating…' : (artist ? '${f.total} songs' : f.artist)),
              circle: artist,
              width: 170,
              onTap: f.playlistId.isEmpty ? null : () => context.open(PlaylistScreen(playlistId: f.playlistId, name: f.name)),
            ),
          );
        },
      ),
    );
  }
}

class _LikedTab extends StatelessWidget {
  const _LikedTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final songs = lib.likedSongs;
    if (songs.isEmpty) return const EmptyNote('Songs you like show up here. Liking a song saves it here on every device.', icon: Icons.favorite_border);
    final off = context.watch<OfflineStore>();
    final saved = songs.where((s) => off.has(s.id)).length;
    final busy = off.busy;
    return ListView(children: [
      if (!isDesktop) const DownloadControls(),
      PlayButtons(songs: songs, extra: [
        if (!isDesktop)
        OutlinedButton.icon(
          onPressed: busy || saved == songs.length
              ? null
              : () {
                  context.toast('Downloading ${songs.length - saved} songs to this device');
                  off.downloadAll(songs);
                },
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(saved == songs.length ? Icons.download_done : Icons.download_for_offline_outlined),
          label: Text(saved == songs.length ? 'Downloaded' : 'Download ($saved/${songs.length})'),
        ),
      ]),
      for (var i = 0; i < songs.length; i++) SongTile(song: songs[i], onTap: () => context.player.playSongs(songs, start: i)),
      const SizedBox(height: 24),
    ]);
  }
}

class _AlbumsTab extends StatefulWidget {
  const _AlbumsTab();
  @override
  State<_AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<_AlbumsTab> with AutomaticKeepAliveClientMixin {
  List<Album>? albums;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final off = context.read<OfflineStore>();
    try {
      final a = await context.api.albumList('alphabeticalByName', size: 500);
      if (mounted) setState(() {
        albums = a;
        error = null;
      });
    } catch (e) {
      final local = off.localAlbums();
      if (mounted) setState(() {
        if (local.isNotEmpty) {
          albums = local;
          error = null;
        } else {
          error = e.toString();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ReloadOnReconnect(onReconnect: _load, child: _body());
  }

  Widget _body() {
    if (error != null) return EmptyNote(error!, icon: Icons.error_outline);
    final a = albums;
    if (a == null) return const Center(child: CircularProgressIndicator());
    if (a.isEmpty) return const EmptyNote('No albums downloaded yet.', icon: Icons.album_outlined);
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, childAspectRatio: 0.78),
        itemCount: a.length,
        itemBuilder: (_, i) => CardTile(
          coverId: a[i].coverArt,
          title: a[i].name,
          subtitle: a[i].artist,
          width: 170,
          onTap: () => context.open(AlbumScreen(albumId: a[i].id, name: a[i].name)),
        ),
      ),
    );
  }
}

class _ArtistsTab extends StatefulWidget {
  const _ArtistsTab();
  @override
  State<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends State<_ArtistsTab> with AutomaticKeepAliveClientMixin {
  List<Artist>? artists;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final off = context.read<OfflineStore>();
    try {
      final a = await context.api.artists();
      if (mounted) setState(() {
        artists = a;
        error = null;
      });
    } catch (e) {
      final local = off.localArtists();
      if (mounted) setState(() {
        if (local.isNotEmpty) {
          artists = local;
          error = null;
        } else {
          error = e.toString();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ReloadOnReconnect(onReconnect: _load, child: _body());
  }

  Widget _body() {
    if (error != null) return EmptyNote(error!, icon: Icons.error_outline);
    final a = artists;
    if (a == null) return const Center(child: CircularProgressIndicator());
    if (a.isEmpty) return const EmptyNote('No artists yet.', icon: Icons.person_outline);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: a.length,
        itemBuilder: (_, i) => ListTile(
          leading: Cover(a[i].coverArt, size: 48, circle: true),
          title: Text(a[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: a[i].albumCount > 0 ? Text('${a[i].albumCount} albums', style: TextStyle(color: kMuted)) : null,
          onTap: () => context.open(ArtistScreen(artistId: a[i].id, name: a[i].name)),
        ),
      ),
    );
  }
}

class _OfflineTab extends StatelessWidget {
  const _OfflineTab();
  @override
  Widget build(BuildContext context) {
    final off = context.watch<OfflineStore>();
    final songs = off.songs;
    if (songs.isEmpty && !off.busy) {
      return const EmptyNote('Songs you save for offline listening live on this device only. Use the menu on any song.', icon: Icons.download_for_offline_outlined);
    }
    return ListView(children: [
      const DownloadControls(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Expanded(child: Text('${songs.length} songs · ${fmtBytes(off.bytes)}', style: TextStyle(color: kMuted))),
          TextButton(
            onPressed: songs.isEmpty
                ? null
                : () async {
                    final ok = await confirm(context, 'Remove all offline songs?', 'They stay on your server.', ok: 'Remove');
                    if (ok) await off.clear();
                  },
            child: const Text('Remove all'),
          ),
        ]),
      ),
      if (songs.isNotEmpty) PlayButtons(songs: songs),
      if (off.progress.isNotEmpty) // one bar for the whole batch, however many songs are in flight
        ListTile(
          leading: const Icon(Icons.downloading),
          title: Text(off.batchTotal > 1 ? 'Saving ${off.batchDone} of ${off.batchTotal}...' : 'Saving...'),
          subtitle: LinearProgressIndicator(
            value: off.batchTotal == 0 ? null : ((off.batchDone + off.progress.values.fold<double>(0, (a, b) => a + b)) / off.batchTotal).clamp(0.0, 1.0),
          ),
        ),
      for (var i = 0; i < songs.length; i++) SongTile(song: songs[i], onTap: () => context.player.playSongs(songs, start: i)),
    ]);
  }
}
