// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:receiptnest/main.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/data/services/auth/auth_service.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    final authService = _FakeAuthService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
        ],
        child: const SmartReceiptApp(),
      ),
    );

    await tester.pump();
    expect(find.byType(SmartReceiptApp), findsOneWidget);
  });
}

class _FakeAuthService implements AuthService {
  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(null);

  @override
  Future<AppUser?> signInAnonymously() async => null;

  @override
  Future<AppUser?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async =>
      null;

  @override
  Future<AppUser?> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async =>
      null;

  @override
  Future<void> signOut() async {}
}
