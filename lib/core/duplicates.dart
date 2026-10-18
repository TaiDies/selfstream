import 'models.dart';

// Words that mark a different version of the same song: "(Instrumental)", "- 2011 Remaster", "[Live at ...]".
final RegExp _versionWord = RegExp(
  r'\b(?:instrumental|remaster(?:ed)?|re-master(?:ed)?|live|acoustic|remix|mix|version|edit|mono|stereo|deluxe|explicit|clean|radio|karaoke|demo|extended|'
  r'sped up|slowed|reverb|bonus|anniversary|reprise|a cappella|acapella|unplugged|session|original|cover)\b',
  caseSensitive: false,
);
final RegExp _bracketed = RegExp(r'\s*[\(\[][^\)\]]*[\)\]]');
final RegExp _dashTail = RegExp(r'\s+[-–—]\s+([^-–—]*)$');

/// The song's title without version tags: "Dumb (2021 Remaster)" and "Dumb - Instrumental" both give "dumb".
String baseTitle(String title) {
  var s = title.trim();
  s = s.replaceAllMapped(_bracketed, (m) => _versionWord.hasMatch(m[0]!) ? '' : m[0]!);
  for (var i = 0; i < 3; i++) {
    final m = _dashTail.firstMatch(s);
    if (m == null || !_versionWord.hasMatch(m[1]!)) break;
    s = s.substring(0, m.start);
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  return s.isEmpty ? title.trim().toLowerCase() : s;
}

String _mainArtist(String artist) {
  final first = artist.toLowerCase().split(RegExp(r'\s*(?:,|&|\bfeat\.?\b|\bft\.?\b|\bx\b|\band\b)\s*')).first.trim();
  return first.isEmpty ? artist.toLowerCase().trim() : first;
}

/// The same song in more than one version: they share an artist and a base title.
class DuplicateGroup {
  DuplicateGroup(this.versions);
  final List<Song> versions;

  /// The version without tags if there is one (else the shortest title), shown as the group's name.
  Song get plain {
    for (final s in versions) {
      if (baseTitle(s.title) == s.title.trim().toLowerCase()) return s;
    }
    return versions.reduce((a, b) => a.title.length <= b.title.length ? a : b);
  }
}

/// Groups of songs in [songs] that are versions of each other, in the order they first appear.
List<DuplicateGroup> findDuplicates(List<Song> songs) {
  final groups = <String, List<Song>>{};
  for (final s in songs) {
    if (s.title.trim().isEmpty) continue;
    groups.putIfAbsent('${_mainArtist(s.artist)}|${baseTitle(s.title)}', () => []).add(s);
  }
  return [for (final g in groups.values) if (g.length > 1) DuplicateGroup(g)];
}
