import 'package:flutter/foundation.dart';

class AppLogger {
  static const bool enableLogs = false;

  static void log(String message) {
    if (enableLogs && kDebugMode) {
      debugPrint(message);
    }
  }

  static void error(String message) {
    if (enableLogs && kDebugMode) {
      debugPrint('ERROR: $message');
    }
  }
}
