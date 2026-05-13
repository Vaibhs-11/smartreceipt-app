import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

class AppCheckInitializer {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    print(
      "App Check build modes: kDebugMode=$kDebugMode, "
      "kReleaseMode=$kReleaseMode, kProfileMode=$kProfileMode",
    );

    // Debug builds: use Debug provider.
    final androidProvider =
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity;

    // Release builds: use real providers.
    final appleProvider =
        kDebugMode ? AppleProvider.debug : AppleProvider.appAttest;

    print(
      "App Check Apple provider selected: "
      "${_appleProviderName(appleProvider)}",
    );

    await FirebaseAppCheck.instance.activate(
      androidProvider: androidProvider,
      appleProvider: appleProvider,
    );
    print("App Check activated for ${_appleProviderName(appleProvider)}");
  }

  static String _appleProviderName(AppleProvider provider) {
    switch (provider) {
      case AppleProvider.debug:
        return "AppleProvider.debug";
      case AppleProvider.appAttest:
        return "AppleProvider.appAttest";
      case AppleProvider.appAttestWithDeviceCheckFallback:
        return "AppleProvider.appAttestWithDeviceCheckFallback";
      case AppleProvider.deviceCheck:
        return "AppleProvider.deviceCheck";
    }
  }
}
