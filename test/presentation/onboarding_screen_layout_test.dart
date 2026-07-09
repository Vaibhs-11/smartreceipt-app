import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/presentation/screens/onboarding_screen.dart';

void main() {
  testWidgets('onboarding screen renders without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(460, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: OnboardingScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ReceiptNest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
