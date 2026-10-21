import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:selfstream/core/api.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('a "wrong username or password" answer from the server signals that the login is gone', () async {
    final api = Api(
      server: 'http://x',
      user: 'u',
      password: 'old',
      client: MockClient((req) async => _json({
            'subsonic-response': {'status': 'failed', 'version': '1.16.1', 'error': {'code': 40, 'message': 'Wrong username or password'}}
          })),
    );
    final fired = Completer<void>();
    api.authLost.listen((_) => fired.complete());
    await expectLater(api.sub('getPlaylists'), throwsA(isA<ApiException>()));
    await fired.future.timeout(const Duration(seconds: 2));
    api.close();
  });

  test('other failures (server down, other errors) do not sign anyone out', () async {
    var n = 0;
    final api = Api(
      server: 'http://x',
      user: 'u',
      password: 'p',
      client: MockClient((req) async => ++n == 1
          ? http.Response('bad gateway', 502)
          : _json({
              'subsonic-response': {'status': 'failed', 'version': '1.16.1', 'error': {'code': 70, 'message': 'not found'}}
            })),
    );
    var fired = false;
    api.authLost.listen((_) => fired = true);
    await api.sub('ping').then((_) {}, onError: (_) {});
    await api.sub('getSong').then((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fired, isFalse);
    api.close();
  });
}
