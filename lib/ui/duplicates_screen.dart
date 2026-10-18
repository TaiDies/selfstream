import 'package:flutter/material.dart';

import '../core/duplicates.dart';
import '../core/models.dart';
import 'widgets.dart';

/// Songs in a playlist that are versions of each other (plain, instrumental, remastered...). Each song shows once;
/// open it to choose which versions to keep. Starts with only the plain version kept.
class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key, required this.playlistId, required this.groups});
  final String playlistId;
  final List<DuplicateGroup> groups;
  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  /// playlistItemIds that will be removed
  final Set<int> _remove = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final g in widget.groups) {
      final keep = g.plain;
      for (final s in g.versions) {
        final id = s.playlistItemId;
        if (id != null && !identical(s, keep)) _remove.add(id);
      }
    }
  }

  int _kept(DuplicateGroup g) => g.versions.where((s) => !_remove.contains(s.playlistItemId)).length;

  void _toggle(DuplicateGroup g, Song s, bool keep) {
    final id = s.playlistItemId;
    if (id == null) return;
    if (!keep && _kept(g) <= 1) {
      context.toast('Keep at least one version of each song');
      return;
    }
    setState(() => keep ? _remove.remove(id) : _remove.add(id));
  }

  Future<void> _apply() async {
    final n = _remove.length;
    final ok = await confirm(context, 'Remove $n ${n == 1 ? 'song' : 'songs'}?', 'They are taken out of this playlist only. Your library is not changed.', ok: 'Remove');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final api = context.api;
    final lib = context.lib;
    var failed = 0;
    for (final id in _remove.toList()) {
      try {
        await api.removeFromPlaylist(widget.playlistId, id);
        _remove.remove(id);
      } catch (_) {
        failed++;
      }
    }
    try {
      await lib.refresh();
    } catch (_) {}
    if (!mounted) return;
    if (failed > 0) {
      setState(() => _busy = false);
      context.toast('$failed could not be removed. Try again.');
    } else {
      context.toast('Duplicates removed');
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _remove.length;
    return PageFrame(
      title: 'Remove duplicates',
      body: Column(children: [
        Expanded(
          child: ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '${widget.groups.length} ${widget.groups.length == 1 ? 'song has' : 'songs have'} more than one version. Only the plain version is kept to start with. '
                'Open a song to choose which versions to keep.',
                style: TextStyle(color: kMuted),
              ),
            ),
            for (final g in widget.groups)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Cover(g.plain.coverArt, size: 44),
                  title: Text(baseTitleShown(g), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${g.plain.artist} · ${g.versions.length} versions · keeping ${_kept(g)}', style: TextStyle(color: kMuted, fontSize: 12)),
                  children: [
                    for (final s in g.versions)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: !_remove.contains(s.playlistItemId),
                        onChanged: _busy ? null : (v) => _toggle(g, s, v ?? false),
                        title: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text([if (s.album.isNotEmpty) s.album, if (s.duration > 0) fmtDuration(s.duration), if (s.isCloud) 'cloud'].join(' · '),
                            style: TextStyle(color: kMuted, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (n == 0 || _busy) ? null : _apply,
                child: Text(_busy ? 'Removing...' : (n == 0 ? 'Nothing to remove' : 'Remove $n ${n == 1 ? 'song' : 'songs'}')),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  String baseTitleShown(DuplicateGroup g) => g.plain.title;
}
