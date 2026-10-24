import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'settings.dart';

/// Keeps the next songs of the queue as files on this device, so they start at once and keep playing
/// when the connection drops. Files live in the temporary folder and are removed when they are no longer needed.
class QueueCache {
  QueueCache({required this.api, required this.settings});
  final Api api;
  final Settings settings;

  Directory? _dir;
  final Map<String, String> _done = {};
  final Set<String> _busy = {};
  Set<String> _wanted = {};
  http.Client? _http;
  int _gen = 0;

  /// The file for this song if it has been saved completely.
  String? pathFor(Song s) {
    final p = _done[s.id];
    if (p == null) return null;
    if (File(p).existsSync()) return p;
    _done.remove(s.id);
    return null;
  }

  Future<Directory?> _ready() async {
    if (_dir != null) return _dir;
    try {
      final base = await getTemporaryDirectory();
      final d = Directory('${base.path}/queue_cache');
      if (d.existsSync()) d.deleteSync(recursive: true); // left over from an earlier run
      d.createSync(recursive: true);
      _dir = d;
    } catch (_) {}
    return _dir;
  }

  /// Stops everything in progress (partly saved files are dropped); songs already saved stay.
  void cancelAll() {
    _gen++;
    _wanted = {};
  }

  /// Saves [want] one after the other, in order; calls [onReady] as each one is complete.
  /// Files for songs that are neither in [want] nor in [keep] are deleted.
  Future<void> fill(List<Song> want, {Set<String> keep = const {}, required void Function(Song, String) onReady}) async {
    final gen = ++_gen;
    final dir = await _ready();
    if (dir == null) return;
    _wanted = {...want.map((s) => s.id), ...keep};
    for (final id in _done.keys.toList()) {
      if (_wanted.contains(id)) continue;
      try {
        File(_done[id]!).deleteSync();
      } catch (_) {}
      _done.remove(id);
    }
    for (final s in want) {
      if (gen != _gen || _disposed) return;
      if (_done.containsKey(s.id) || _busy.contains(s.id)) continue;
      _busy.add(s.id);
      try {
        final path = await _fetch(s, dir);
        if (path != null) {
          _done[s.id] = path;
          if (!_disposed) onReady(s, path);
        }
      } finally {
        _busy.remove(s.id);
      }
    }
  }

  Future<String?> _fetch(Song s, Directory dir) async {
    final file = File('${dir.path}/${s.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.audio');
    final client = _http ??= http.Client();
    var aborted = false;
    try {
      final res = await client.send(http.Request('GET', api.streamUri(s.id, maxBitRate: settings.maxBitRate))).timeout(const Duration(seconds: 45));
      if (res.statusCode >= 300) return null;
      final sink = file.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          if (_disposed || !_wanted.contains(s.id)) {
            aborted = true;
            break;
          }
          sink.add(chunk);
          got += chunk.length;
        }
      } finally {
        await sink.close();
      }
      final total = res.contentLength ?? 0;
      final cut = total > 0 && got != total && res.headers['content-encoding'] == null;
      if (aborted || cut || got < 1000) {
        _remove(file);
        return null;
      }
      return file.path;
    } catch (_) {
      _remove(file);
      return null;
    }
  }

  void _remove(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _http?.close();
    _http = null;
    final d = _dir;
    if (d != null) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}
