import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Where new Windows builds are published (a GitHub release called "windows-latest").
const String kUpdateRepo = 'TaiDies/selfstream';

/// The build this app was made from, set by the build script (--dart-define=BUILD_NUMBER=...). 0 = a local build.
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

class UpdateInfo {
  const UpdateInfo(this.build, this.url, this.size, this.notes);
  final int build;
  final String url;
  final int size;
  final String notes;
}

/// Looks for a newer installer on GitHub and runs it. Windows only.
class Updater {
  static bool get supported => Platform.isWindows && kBuildNumber > 0;

  /// The newer build, or null if this one is current (or GitHub cannot be reached).
  static Future<UpdateInfo?> check({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/tags/windows-latest'),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return parse(jsonDecode(utf8.decode(res.bodyBytes)), kBuildNumber);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Reads a GitHub release; returns the installer if its build is newer than [current].
  static UpdateInfo? parse(Object? release, int current) {
    if (release is! Map) return null;
    final body = '${release['body'] ?? ''}';
    final m = RegExp(r'Build:\s*(\d+)').firstMatch(body);
    final build = m == null ? 0 : int.parse(m.group(1)!);
    if (build <= current) return null;
    for (final a in (release['assets'] as List? ?? const [])) {
      if (a is Map && a['name'] == 'selfstream-setup.exe') {
        final url = '${a['browser_download_url'] ?? ''}';
        // only ever run something that came from this project's GitHub releases
        if (!url.startsWith('https://github.com/$kUpdateRepo/releases/download/')) return null;
        return UpdateInfo(build, url, (a['size'] as num?)?.toInt() ?? 0, body.replaceAll(RegExp(r'Build:\s*\d+'), '').trim());
      }
    }
    return null;
  }

  /// Downloads the installer, reporting progress 0..1. Returns the saved file.
  static Future<File> download(UpdateInfo u, void Function(double) progress) async {
    final c = http.Client();
    try {
      final res = await c.send(http.Request('GET', Uri.parse(u.url)));
      if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode})');
      final total = res.contentLength ?? u.size;
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}selfstream-setup-${u.build}.exe');
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress(got / total);
      }
      await sink.close();
      if (total > 0 && got != total) throw Exception('The download was cut short');
      return file;
    } finally {
      c.close();
    }
  }

  /// Starts the installer quietly; it closes this app, replaces the files and starts the new one.
  static Future<void> install(File setup) async {
    await Process.start(setup.path, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached);
    exit(0);
  }
}
