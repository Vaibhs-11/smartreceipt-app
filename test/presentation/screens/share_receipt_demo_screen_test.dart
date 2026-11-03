import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/presentation/screens/share_receipt_demo_screen.dart';

void main() {
  testWidgets('moves through all three Share Receipt demo steps', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ShareReceiptDemoScreen()),
    );

    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Back'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
}
