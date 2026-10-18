import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import 'updater.dart';

/// True in the build uploaded to Google Play (--dart-define=PLAY_BUILD=true). Google Play updates that one.
const bool kPlayBuild = bool.fromEnvironment('PLAY_BUILD');

class AndroidUpdate {
  const AndroidUpdate(this.build, this.version, this.size);
  final int build;
  final String version;
  final int size;
}

/// Android updates. A test build (APK) asks your selfstream server for a newer APK; the Play Store build asks Google Play.
class AndroidUpdater {
  static bool get fromServer => Platform.isAndroid && !kPlayBuild && kBuildNumber > 0;
  static bool get fromPlay => Platform.isAndroid && kPlayBuild;
  static bool get supported => fromServer || fromPlay;

  static Uri _url(Api api, String path) =>
      Uri.parse('${api.server}/selfstream/api/v1/$path').replace(queryParameters: api.authParams());

  /// A newer APK on the server, or null (none there, not newer, or the server cannot be reached).
  static Future<AndroidUpdate?> check(Api api, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(_url(api, 'app/android')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return parse(jsonDecode(utf8.decode(res.bodyBytes)), kBuildNumber);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  static AndroidUpdate? parse(Object? json, int current) {
    if (json is! Map) return null;
    final build = (json['build'] as num?)?.toInt() ?? 0;
    if (build <= current) return null;
    return AndroidUpdate(build, '${json['version'] ?? ''}', (json['size'] as num?)?.toInt() ?? 0);
  }

  static Future<File> download(Api api, AndroidUpdate u, void Function(double) progress) async {
    final c = http.Client();
    try {
      final res = await c.send(http.Request('GET', _url(api, 'app/android/download')));
      if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode})');
      final total = res.contentLength ?? u.size;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}selfstream-${u.build}.apk');
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

  /// Hands the APK to Android's installer (it may ask once to allow installs from Selfstream).
  static Future<void> install(File apk) async {
    final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) throw Exception(r.message);
  }

  /// Google Play: download a newer version in the background, then restart into it. False when none is waiting
  /// (or the app was not installed from Google Play).
  static Future<bool> playUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return false;
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      } else if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
