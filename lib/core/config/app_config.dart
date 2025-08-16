import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppConfig {
  const AppConfig({
    required this.useStubs,
    required this.isPremium,
  });

  final bool useStubs;
  final bool isPremium;

  factory AppConfig.fromEnv() {
    if (!dotenv.isInitialized) {
      return AppConfig(
        useStubs: true || kDebugMode,
        isPremium: false,
      );
    }
    final String useStubsEnv = dotenv.maybeGet('USE_STUBS') ?? 'true';
    final String isPremiumEnv = dotenv.maybeGet('PREMIUM') ?? 'false';
    final bool useStubs = useStubsEnv.toLowerCase() != 'false';
    final bool isPremium = isPremiumEnv.toLowerCase() == 'true';
    return AppConfig(useStubs: useStubs || kDebugMode, isPremium: isPremium);
  }
}

final Provider<AppConfig> appConfigProvider = Provider<AppConfig>((_) {
  return AppConfig.fromEnv();
});


