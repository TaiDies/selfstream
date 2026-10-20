import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/core/api.dart';
import 'package:selfstream/state/obs_overlay.dart';
import 'package:selfstream/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the overlay is served on this computer only and holds no login', () async {
    SharedPreferences.setMockInitialValues({'obsOverlay': true});
    final settings = Settings(await SharedPreferences.getInstance());
    final api = Api(server: 'http://127.0.0.1:1', user: 'u', password: 'secret-password');
    final source = _Nothing();
    final overlay = ObsOverlay(api, settings, source)..start();
    for (var i = 0; i < 50 && overlay.port == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(overlay.port, isNotNull);
    expect(overlay.link, startsWith('http://localhost:${overlay.port}/overlay'));

    final client = HttpClient();
    Future<(int, String)> get(String path, {String? host}) async {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:${overlay.port}$path'));
      if (host != null) req.headers.host = host;
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    }

    final page = await get('/overlay');
    expect(page.$1, 200);
    expect(page.$2, contains('Selfstream overlay'));
    expect(page.$2, isNot(contains('secret-password')));
    expect(jsonDecode((await get('/state')).$2), {'song': false}); // nothing playing yet
    expect((await get('/nope')).$1, 404);
    expect((await get('/overlay', host: 'evil.example')).$1, 403); // not reachable under another name

    settings.obsOverlay = false; // switching it off closes the port
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(overlay.port, isNull);
    client.close(force: true);
    overlay.dispose();
  });
}

class _Nothing implements OverlaySource {
  @override
  Map<String, Object?> state() => {'song': false};
  @override
  String? currentCover() => null;
  @override
  String? savedCoverPath() => null;
}
