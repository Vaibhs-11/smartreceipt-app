import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/core/services/share_receipt_demo_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'user-123';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('requires a saved receipt before showing the demo prompt', () async {
    expect(
      await ShareReceiptDemoPreferences.shouldShow(
        userId: userId,
        hasSavedReceipt: false,
      ),
      isFalse,
    );
    expect(
      await ShareReceiptDemoPreferences.shouldShow(
        userId: userId,
        hasSavedReceipt: true,
      ),
      isTrue,
    );
  });

  test('dismissal suppresses the prompt for that account', () async {
    await ShareReceiptDemoPreferences.markDismissed(userId);

    expect(
      await ShareReceiptDemoPreferences.shouldShow(
        userId: userId,
        hasSavedReceipt: true,
      ),
      isFalse,
    );
    expect(
      await ShareReceiptDemoPreferences.shouldShow(
        userId: 'another-user',
        hasSavedReceipt: true,
      ),
      isTrue,
    );
  });

  test('completion suppresses the prompt', () async {
    await ShareReceiptDemoPreferences.markCompleted(userId);

    expect(
      await ShareReceiptDemoPreferences.shouldShow(
        userId: userId,
        hasSavedReceipt: true,
      ),
      isFalse,
    );
  });

  test('a successful Share Sheet save suppresses the prompt', () async {
    final previousRevision = ShareReceiptDemoPreferences.revision.value;
    await ShareReceiptDemoPreferences.markShareUsed(userId);

    expect(
      ShareReceiptDemoPreferences.revision.value,
      previousRevision + 1,
    );
    expect(
      await ShareReceiptDemoPreferences.shouldShow(
        userId: userId,
        hasSavedReceipt: true,
      ),
      isFalse,
    );
  });
}
