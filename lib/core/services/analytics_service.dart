import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:receiptnest/core/utils/app_logger.dart';

class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  static Future<void> logSignUp() async {
    await _analytics.logEvent(name: 'sign_up');
  }

  static Future<void> logLogin() async {
    await _analytics.logEvent(name: 'login');
  }

  static Future<void> logSearchUsed({
    required String searchArea,
    required int queryLength,
  }) async {
    await _analytics.logEvent(
      name: 'search_used',
      parameters: {
        'search_area': searchArea,
        'query_length': queryLength,
      },
    );
  }

  static Future<void> logShareReceiptDemoShown() async {
    await _logEventSafely(name: 'share_demo_shown');
  }

  static Future<void> logShareReceiptDemoOpened(
      {required String source}) async {
    await _logEventSafely(
      name: 'share_demo_opened',
      parameters: {'source': source},
    );
  }

  static Future<void> logShareReceiptDemoDismissed() async {
    await _logEventSafely(name: 'share_demo_dismissed');
  }

  static Future<void> logShareReceiptDemoCompleted({
    required String source,
  }) async {
    await _logEventSafely(
      name: 'share_demo_completed',
      parameters: {'source': source},
    );
  }

  static Future<void> logReceiptSavedFromShare() async {
    await _logEventSafely(name: 'receipt_saved_from_share');
  }

  static Future<void> _logEventSafely({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (error) {
      AppLogger.error('Could not log analytics event $name: $error');
    }
  }
}
