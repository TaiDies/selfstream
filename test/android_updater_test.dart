import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/state/android_updater.dart';

void main() {
  test('only a newer build on the server is offered', () {
    expect(AndroidUpdater.parse({'build': 11, 'version': '0.3.0', 'size': 5}, 10)?.build, 11);
    expect(AndroidUpdater.parse({'build': 10, 'version': '0.3.0'}, 10), isNull);
    expect(AndroidUpdater.parse({'build': 9}, 10), isNull);
    expect(AndroidUpdater.parse('nonsense', 10), isNull);
    expect(AndroidUpdater.parse({'version': '0.3.0'}, 0), isNull);
  });
}
