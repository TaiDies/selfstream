import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Covers for Android Auto and other media controllers outside the app.
///
/// They cannot fetch an https address (or read a file inside the app), so the cover is copied into a cache
/// folder and handed out as a content:// address served by the app's CoverProvider (see tool/android_widgets).
class AutoCovers {
  static const authority = 'dev.selfstream.selfstream.covers';
  static Directory? _dir;

  static String _name(String coverId) => '${md5.convert(utf8.encode(coverId))}.jpg';

  /// The content address of a cover (the file may not be there yet; see [ensure]).
  static Uri uriFor(String coverId) => Uri.parse('content://$authority/${_name(coverId)}');

  /// Makes sure the cover file exists, copying it from [source] (a file on this device) or downloading it.
  static Future<void> ensure(String coverId, Uri source) async {
    if (coverId.isEmpty || !Platform.isAndroid) return;
    try {
      final dir = _dir ??= Directory('${(await getTemporaryDirectory()).path}/auto_covers')..createSync(recursive: true);
      final file = File('${dir.path}/${_name(coverId)}');
      if (file.existsSync() && file.lengthSync() > 0) return;
      if (source.scheme == 'file') {
        await File.fromUri(source).copy(file.path);
      } else {
        final r = await http.get(source).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) await file.writeAsBytes(r.bodyBytes, flush: true);
      }
    } catch (_) {}
  }
}
