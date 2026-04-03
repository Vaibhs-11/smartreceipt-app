import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

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
}
