import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/core/api.dart';

void main() {
  test('a cover keeps the same address, so it is not fetched again when a screen redraws', () {
    final api = Api(server: 'http://x', user: 'u', password: 'sesame');
    expect(api.coverUri('al-1', size: 120), api.coverUri('al-1', size: 120));
    expect(api.coverUri('al-1', size: 120), isNot(api.coverUri('al-1', size: 240)));
    expect(api.coverUri('al-1', size: 120), isNot(api.coverUri('al-2', size: 120)));
  });
}
