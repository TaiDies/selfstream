import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline mode is offered only to someone who has signed in here before', () async {
    SharedPreferences.setMockInitialValues({});
    final fresh = Session();
    await fresh.load();
    expect(fresh.signedIn, isFalse);
    expect(fresh.canUseOffline, isFalse);
    await fresh.enterOfflineMode(); // does nothing without a previous login
    expect(fresh.signedIn, isFalse);

    SharedPreferences.setMockInitialValues({'server': 'http://192.168.1.50:8080', 'user': 'me'}); // signed out earlier
    final again = Session();
    await again.load();
    expect(again.signedIn, isFalse); // a signed-out app does not open by itself
    expect(again.canUseOffline, isTrue);
  });
}
