import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfstream/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('starts on the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final vault = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        switch (call.method) {
          case 'write':
            vault['${args['key']}'] = '${args['value']}';
            return null;
          case 'read':
            return vault['${args['key']}'];
          case 'delete':
            vault.remove('${args['key']}');
            return null;
        }
        return null;
      },
    );
    await tester.pumpWidget(const SelfstreamApp());
    await tester.pumpAndSettle();
    expect(find.text('Selfstream'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
