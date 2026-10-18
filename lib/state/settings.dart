import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small per-device preferences.
class Settings extends ChangeNotifier {
  Settings(this._p);
  final SharedPreferences _p;

  /// 0 = original quality, otherwise the highest kbit/s the server may send (it transcodes library songs).
  int get maxBitRate => _p.getInt('maxBitRate') ?? 0;
  set maxBitRate(int v) {
    _p.setInt('maxBitRate', v);
    notifyListeners();
  }

  String get themeId => _p.getString('themeId') ?? 'emerald';
  set themeId(String v) {
    _p.setString('themeId', v);
    notifyListeners();
  }

  /// The user's own theme: one colour (ARGB), light or dark, and an optional picture behind the app.
  int get customAccent => _p.getInt('customAccent') ?? 0xFF1ED760;
  set customAccent(int v) {
    _p.setInt('customAccent', v);
    notifyListeners();
  }

  bool get customLight => _p.getBool('customLight') ?? false;
  set customLight(bool v) {
    _p.setBool('customLight', v);
    notifyListeners();
  }

  /// Pure black background (saves power on OLED screens), whatever colour is picked.
  bool get customOled => _p.getBool('customOled') ?? false;
  set customOled(bool v) {
    _p.setBool('customOled', v);
    notifyListeners();
  }

  /// Path of the picture on this device ('' = none).
  String get customPicture => _p.getString('customPicture') ?? '';
  set customPicture(String v) {
    _p.setString('customPicture', v);
    notifyListeners();
  }

  /// How strongly the picture is darkened (0.3 to 0.9).
  double get customDim => (_p.getDouble('customDim') ?? 0.6).clamp(0.3, 0.9);
  set customDim(double v) {
    _p.setDouble('customDim', v.clamp(0.3, 0.9));
    notifyListeners();
  }

  /// Keyboard shortcuts the user changed (JSON, see hotkeys.dart). Empty = all defaults.
  String get hotkeys => _p.getString('hotkeys') ?? '';
  set hotkeys(String v) {
    _p.setString('hotkeys', v);
    notifyListeners();
  }

  List<String> get recentSearches => List<String>.of(_p.getStringList('recentSearches') ?? const <String>[]);

  void addRecentSearch(String q) {
    final t = q.trim();
    if (t.length < 2) return;
    final list = recentSearches..removeWhere((e) => e.toLowerCase() == t.toLowerCase());
    list.insert(0, t);
    _p.setStringList('recentSearches', list.take(30).toList());
    notifyListeners();
  }

  void removeRecentSearch(String q) {
    _p.setStringList('recentSearches', recentSearches..remove(q));
    notifyListeners();
  }

  void clearRecentSearches() {
    _p.remove('recentSearches');
    notifyListeners();
  }

  /// Liking a YouTube song also downloads it into the server library (off: the like is only remembered).
  bool get likeDownloadsToServer => _p.getBool('likeDownloadsToServer') ?? false;
  set likeDownloadsToServer(bool v) {
    _p.setBool('likeDownloadsToServer', v);
    notifyListeners();
  }

  /// Computer volume, 0..1 (phones use their own volume keys).
  double get volume => (_p.getDouble('volume') ?? 1.0).clamp(0.0, 1.0);
  set volume(double v) {
    _p.setDouble('volume', v.clamp(0.0, 1.0));
  }

  /// Windows: show what is playing on Discord. The id is optional, the server can supply one.
  bool get discordPresence => _p.getBool('discordPresence') ?? true;
  set discordPresence(bool v) {
    _p.setBool('discordPresence', v);
    notifyListeners();
  }


  /// Report what you listen to, for Stats and Discover.
  bool get trackListening => _p.getBool('trackListening') ?? true;
  set trackListening(bool v) {
    _p.setBool('trackListening', v);
    notifyListeners();
  }

  /// Listens that could not be sent yet (no connection); sent with the next one.
  List<Map<String, dynamic>> get pendingPlays {
    final raw = _p.getString('pendingPlays');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  set pendingPlays(List<Map<String, dynamic>> v) {
    final trimmed = v.length > 500 ? v.sublist(v.length - 500) : v;
    _p.setString('pendingPlays', jsonEncode(trimmed));
  }

  // ---- Lyrics appearance ----
  /// Text size of a lyric line (the line being sung is a little larger).
  double get lyricsSize => (_p.getDouble('lyricsSize') ?? 20).clamp(12.0, 40.0);
  set lyricsSize(double v) {
    _p.setDouble('lyricsSize', v.clamp(12.0, 40.0));
    notifyListeners();
  }

  /// 0 = left, 1 = center, 2 = right.
  int get lyricsAlign => (_p.getInt('lyricsAlign') ?? 0).clamp(0, 2);
  set lyricsAlign(int v) {
    _p.setInt('lyricsAlign', v.clamp(0, 2));
    notifyListeners();
  }

  /// Font weight index: 0 = regular, 1 = medium, 2 = bold, 3 = extra bold.
  int get lyricsWeight => (_p.getInt('lyricsWeight') ?? 3).clamp(0, 3);
  set lyricsWeight(int v) {
    _p.setInt('lyricsWeight', v.clamp(0, 3));
    notifyListeners();
  }

  /// Space between lines, in logical pixels.
  double get lyricsSpacing => (_p.getDouble('lyricsSpacing') ?? 12).clamp(0.0, 40.0);
  set lyricsSpacing(double v) {
    _p.setDouble('lyricsSpacing', v.clamp(0.0, 40.0));
    notifyListeners();
  }

  /// How faint the lines that are not being sung are (0.2 .. 1).
  double get lyricsDim => (_p.getDouble('lyricsDim') ?? 0.45).clamp(0.2, 1.0);
  set lyricsDim(double v) {
    _p.setDouble('lyricsDim', v.clamp(0.2, 1.0));
    notifyListeners();
  }

  /// The line being sung is drawn in the theme colour instead of white.
  bool get lyricsAccent => _p.getBool('lyricsAccent') ?? false;
  set lyricsAccent(bool v) {
    _p.setBool('lyricsAccent', v);
    notifyListeners();
  }

  /// Keep the line being sung in the middle of the view.
  bool get lyricsAutoScroll => _p.getBool('lyricsAutoScroll') ?? true;
  set lyricsAutoScroll(bool v) {
    _p.setBool('lyricsAutoScroll', v);
    notifyListeners();
  }

  void resetLyrics() {
    for (final k in ['lyricsSize', 'lyricsAlign', 'lyricsWeight', 'lyricsSpacing', 'lyricsDim', 'lyricsAccent', 'lyricsAutoScroll']) {
      _p.remove(k);
    }
    notifyListeners();
  }

  // ---- Updates (Windows installer) ----
  bool get checkUpdates => _p.getBool('checkUpdates') ?? true;
  set checkUpdates(bool v) {
    _p.setBool('checkUpdates', v);
    notifyListeners();
  }

  /// A build the user chose to skip; the app stops asking about it.
  int get skippedBuild => _p.getInt('skippedBuild') ?? 0;
  set skippedBuild(int v) {
    _p.setInt('skippedBuild', v);
  }
}
