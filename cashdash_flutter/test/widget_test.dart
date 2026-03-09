import 'package:flutter_test/flutter_test.dart';

import 'package:cashdash_flutter/main.dart';

void main() {
  testWidgets('CashDashApp starts on Splash', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CashDashApp());

    // Wait for the splash screen animations if needed
    await tester.pumpAndSettle();
  });
}
