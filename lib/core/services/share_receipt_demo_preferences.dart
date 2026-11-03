import 'package:flutter/foundation.dart';
import 'package:receiptnest/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShareReceiptDemoState { dismissed, completed, shareUsed }

/// Stores the versioned, per-account state for the Share Sheet tutorial.
///
/// Keeping the campaign id in the key lets a future, materially different
/// tutorial be offered without disturbing this release's choice.
class ShareReceiptDemoPreferences {
  ShareReceiptDemoPreferences._();

  static const String campaignId = 'share_receipt_demo_v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String preferenceKeyFor(String userId) => '$campaignId:$userId';

  static Future<bool> shouldShow({
    required String userId,
    required bool hasSavedReceipt,
  }) async {
    if (!hasSavedReceipt) return false;

    try {
      final preferences = await SharedPreferences.getInstance();
      return !preferences.containsKey(preferenceKeyFor(userId));
    } catch (error) {
      AppLogger.error('Could not read Share Receipt demo state: $error');
      return false;
    }
  }

  static Future<void> markDismissed(String userId) =>
      _writeState(userId, ShareReceiptDemoState.dismissed);

  static Future<void> markCompleted(String userId) =>
      _writeState(userId, ShareReceiptDemoState.completed);

  static Future<void> markShareUsed(String userId) =>
      _writeState(userId, ShareReceiptDemoState.shareUsed);

  static Future<void> _writeState(
    String userId,
    ShareReceiptDemoState state,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(preferenceKeyFor(userId), state.name);
      revision.value++;
    } catch (error) {
      AppLogger.error('Could not save Share Receipt demo state: $error');
    }
  }
}
