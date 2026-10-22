import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../platform/platform.dart';
import 'settings.dart';

/// Songs saved on this device so they play without a connection.
class OfflineStore extends ChangeNotifier {
  OfflineStore(this.api, this.settings);
  final Api api;
  final Settings settings;

  Directory? _dir;
  final Map<String, Map<String, dynamic>> _index = {}; // song id -> {file, song}
  final Map<String, double> progress = {}; // song id -> 0..1 while downloading
  final Map<String, String> failed = {};

  // The current run of downloads (a queue worked through one song at a time), for the controls and the notification.
  int batchTotal = 0, batchDone = 0, batchFailed = 0;
  final List<_Job> _queue = [];
  final Set<_Job> _active = {}; // songs being downloaded right now (several at once: one is mostly waiting on the server)
  static const int _parallel = 10;
  bool paused = false;
  int _gen = 0; // moves on at every pause or stop: a download started before that sees it and gives up, later ones are not affected
  http.Client? _http; // shared, so connections are reused between songs
  Timer? _indexTimer;
  bool get busy => _active.isNotEmpty || _queue.isNotEmpty;
  void resetBatch() => batchTotal = batchDone = batchFailed = 0;

  /// Stop after interrupting the song in progress; it starts over from the beginning when resumed.
  void pause() {
    if (!busy || paused) return;
    paused = true;
    _gen++;
    notifyListeners();
  }

  void resume() {
    if (!paused) return;
    paused = false;
    _pump();
    notifyListeners();
  }

  /// Cancel everything that has not finished. Songs already saved stay.
  void stopAll() {
    if (!busy) return;
    for (final j in _queue) {
      j.done.complete();
    }
    _queue.clear();
    batchTotal = batchDone;
    for (final j in _active) {
      j.cancelled = true;
    }
    _gen++;
    paused = false;
    notifyListeners();
  }

  Future<void> load() async {
    if (isDesktop) {
      notifyListeners(); // computers just stream: nothing is saved on them
      return;
    }
    try {
      final base = await getApplicationDocumentsDirectory();
      _dir = Directory('${base.path}/offline');
      await _dir!.create(recursive: true);
      final f = File('${_dir!.path}/index.json');
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as Map;
        data.forEach((k, v) {
          final entry = Map<String, dynamic>.from(v as Map);
          if (File('${_dir!.path}/${entry['file']}').existsSync()) _index['$k'] = entry;
        });
      }
    } catch (_) {
      _dir = null;
    }
    await _loadCovers();
    notifyListeners();
    unawaited(_backfillLyrics());
    unawaited(_backfillCovers());
  }

  // ---- album covers saved with the songs, so they show (and go to the notification) without a connection
  final Set<String> _covers = {};
  static String _coverName(String id) => '${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.jpg';

  /// The saved cover for this cover id, or null if none is on this device.
  File? coverFor(String id) {
    if (id.isEmpty || _dir == null) return null;
    final name = _coverName(id);
    return _covers.contains(name) ? File('${_dir!.path}/covers/$name') : null;
  }

  Future<void> _loadCovers() async {
    try {
      final d = Directory('${_dir!.path}/covers');
      if (!await d.exists()) return;
      await for (final f in d.list()) {
        final name = f.path.split(RegExp(r'[\\/]')).last;
        if (name.endsWith('.jpg') && await File(f.path).length() > 500) _covers.add(name);
      }
    } catch (_) {}
  }

  Future<void> _saveCover(String id) async {
    if (id.isEmpty || _dir == null) return;
    final name = _coverName(id);
    if (_covers.contains(name)) return;
    final client = http.Client();
    try {
      final res = await client.get(api.coverUri(id, size: 600)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.length < 500) return;
      final d = Directory('${_dir!.path}/covers');
      await d.create(recursive: true);
      await File('${d.path}/$name').writeAsBytes(res.bodyBytes);
      _covers.add(name);
      notifyListeners();
    } catch (_) {
    } finally {
      client.close();
    }
  }

  /// Songs saved before covers were kept: fetch theirs now, quietly.
  Future<void> _backfillCovers() async {
    for (final e in _index.values.toList()) {
      try {
        await _saveCover(Song.fromJson(e['song']).coverArt);
      } catch (_) {}
    }
  }

  File? _lyricsFile(String id) {
    final e = _index[id];
    return e == null || _dir == null ? null : File('${_dir!.path}/${e['file']}.lyrics.json');
  }

  /// Lyrics saved next to the audio, so they show without a connection.
  Future<Lyrics?> lyricsFor(String id) async {
    try {
      final f = _lyricsFile(id);
      if (f == null || !await f.exists()) return null;
      return Api.parseLyrics(Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLyrics(String id) async {
    final f = _lyricsFile(id);
    if (f == null || await f.exists()) return;
    final raw = await api.lyricsRaw(id);
    if (raw != null && (raw['structuredLyrics'] as List? ?? []).isNotEmpty) await f.writeAsString(jsonEncode(raw));
  }

  /// Songs saved before lyrics were kept: fetch theirs now, quietly.
  Future<void> _backfillLyrics() async {
    for (final id in _index.keys.toList()) {
      try {
        await _saveLyrics(id);
      } catch (_) {}
    }
  }

  bool get available => _dir != null;
  bool has(String id) => _index.containsKey(id);

  /// The same song counts even if it was saved under another id (library copy vs YouTube copy).
  bool hasSong(Song s) => _index.containsKey(s.id) || _entryByKey(s.key) != null;

  Map<String, dynamic>? _entryByKey(String key) {
    for (final e in _index.values) {
      if (Song.fromJson(e['song']).key == key) return e;
    }
    return null;
  }

  String? pathForSong(Song s) {
    final e = _index[s.id] ?? _entryByKey(s.key);
    return e == null || _dir == null ? null : '${_dir!.path}/${e['file']}';
  }

  // ---- what is on this device, shown as albums and artists when there is no connection
  static String albumIdOf(Song s) => s.albumId.isNotEmpty ? s.albumId : 'local:${s.artist.toLowerCase()}|${s.album.toLowerCase()}';
  static String artistIdOf(Song s) => s.artistId.isNotEmpty ? s.artistId : 'local-artist:${_firstArtist(s.artist).toLowerCase()}';
  static String _firstArtist(String a) => a.split(RegExp(r'\s*(,|&|;)\s*')).first;

  List<Album> localAlbums() {
    final out = <String, Album>{};
    for (final s in songs.where((s) => s.album.isNotEmpty)) {
      out.putIfAbsent(
          albumIdOf(s),
          () => Album({'id': albumIdOf(s), 'name': s.album, 'artist': _firstArtist(s.artist), 'artistId': artistIdOf(s), 'coverArt': s.coverArt}));
    }
    final list = out.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<Artist> localArtists() {
    final out = <String, Artist>{};
    for (final s in songs.where((s) => s.artist.isNotEmpty)) {
      out.putIfAbsent(artistIdOf(s), () => Artist({'id': artistIdOf(s), 'name': _firstArtist(s.artist), 'coverArt': s.coverArt}));
    }
    final list = out.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<Song> songsOfAlbum(String albumId) {
    final list = songs.where((s) => albumIdOf(s) == albumId).toList();
    list.sort((a, b) => a.track.compareTo(b.track));
    return list;
  }

  List<Album> albumsOfArtist(String artistId) => localAlbums().where((a) => a.artistId == artistId).toList();


  String? pathFor(String id) {
    final e = _index[id];
    return e == null || _dir == null ? null : '${_dir!.path}/${e['file']}';
  }

  List<Song> get songs => _index.values.map((e) => Song.fromJson(e['song'])).toList();

  int get bytes {
    var total = 0;
    for (final e in _index.values) {
      try {
        total += File('${_dir!.path}/${e['file']}').lengthSync();
      } catch (_) {}
    }
    return total;
  }

  Future<void> _saveIndex() async {
    if (_dir == null) return;
    await File('${_dir!.path}/index.json').writeAsString(jsonEncode(_index));
  }

  Future<void> download(Song s) => _enqueue(s);

  Future<void> downloadAll(Iterable<Song> songs) => Future.wait(songs.map(_enqueue).toList());

  Future<void> _enqueue(Song s) {
    if (_dir == null || has(s.id) || _active.any((j) => j.song.id == s.id) || _queue.any((j) => j.song.id == s.id)) return Future.value();
    if (!busy) resetBatch();
    final job = _Job(s);
    _queue.add(job);
    batchTotal++;
    notifyListeners();
    _pump();
    return job.done.future;
  }

  /// Starts songs until [_parallel] are in flight.
  void _pump() {
    if (paused) return;
    while (_active.length < _parallel && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active.add(job);
      unawaited(_run(job));
    }
  }

  Future<void> _run(_Job job) async {
    var finished = true;
    try {
      finished = await _fetch(job.song);
    } catch (_) {}
    _active.remove(job);
    if (!finished && !job.cancelled) {
      _queue.insert(0, job); // paused mid-song: start it again on resume
    } else {
      if (!job.cancelled) {
        if (failed.containsKey(job.song.id)) batchFailed++;
        batchDone++;
      }
      job.done.complete();
    }
    if (_active.isEmpty && _queue.isEmpty) {
      _http?.close();
      _http = null;
      await _flushIndex();
    }
    notifyListeners();
    _pump();
  }

  void _saveIndexSoon() {
    _indexTimer ??= Timer(const Duration(seconds: 3), () {
      _indexTimer = null;
      unawaited(_saveIndex());
    });
  }

  Future<void> _flushIndex() async {
    if (_indexTimer == null) return;
    _indexTimer!.cancel();
    _indexTimer = null;
    await _saveIndex();
  }

  /// Saves one song. Returns false if it was interrupted (paused or stopped) before it finished.
  Future<bool> _fetch(Song s) async {
    if (_dir == null || has(s.id)) return true;
    progress[s.id] = 0;
    failed.remove(s.id);
    notifyListeners();
    final name = '${s.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.audio';
    final file = File('${_dir!.path}/$name');
    final client = _http ??= http.Client();
    var interrupted = false;
    var lastTick = DateTime.now();
    final gen = _gen;
    try {
      final res = await client.send(http.Request('GET', api.streamUri(s.id, maxBitRate: settings.maxBitRate)));
      if (res.statusCode >= 300) throw ApiException('Server answered ${res.statusCode}');
      final sink = file.openWrite();
      var received = 0;
      final total = res.contentLength ?? 0;
      await for (final chunk in res.stream) {
        if (_gen != gen) {
          interrupted = true;
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress[s.id] = received / total;
          final now = DateTime.now();
          if (now.difference(lastTick).inMilliseconds > 250) {
            lastTick = now; // redrawing on every chunk would cost more time than the download
            notifyListeners();
          }
        }
      }
      await sink.close();
      if (interrupted) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        return false;
      }
      if (received < 1000) throw ApiException('Empty answer');
      if (total > 0 && received != total && res.headers['content-encoding'] == null) throw ApiException('The download was cut off');
      _index[s.id] = {'file': name, 'song': s.toJson()};
      _saveIndexSoon();
      try {
        await _saveLyrics(s.id);
      } catch (_) {}
      await _saveCover(s.coverArt);
      return true;
    } catch (e) {
      if (_gen != gen) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        return false;
      }
      failed[s.id] = e.toString();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return true;
    } finally {
      progress.remove(s.id);
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    final e = _index.remove(id);
    if (e != null && _dir != null) {
      try {
        final cover = Song.fromJson(e['song']).coverArt;
        if (cover.isNotEmpty && !_index.values.any((x) => Song.fromJson(x['song']).coverArt == cover)) {
          final name = _coverName(cover);
          if (_covers.remove(name)) await File('${_dir!.path}/covers/$name').delete();
        }
      } catch (_) {}
      try {
        await File('${_dir!.path}/${e['file']}').delete();
        final l = File('${_dir!.path}/${e['file']}.lyrics.json');
        if (await l.exists()) await l.delete();
      } catch (_) {}
      await _saveIndex();
    }
    notifyListeners();
  }

  Future<void> clear() async {
    for (final id in _index.keys.toList()) {
      await remove(id);
    }
  }
}

class _Job {
  _Job(this.song);
  final Song song;
  final Completer<void> done = Completer<void>();
  bool cancelled = false;
}
