import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class CrashlyticsLogger {
  static Future<void> recordNonFatal({
    required String reason,
    required Object error,
    StackTrace? stackTrace,
    Map<String, String>? context,
  }) async {
    final crashlytics = FirebaseCrashlytics.instance;
    if (context != null) {
      for (final entry in context.entries) {
        await crashlytics.setCustomKey(entry.key, entry.value);
      }
    }
    await crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: false,
    );
  }
}
