import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/core/constants/app_constants.dart';
import 'package:smartreceipt/core/theme/app_theme.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/add_receipt_screen.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';
import 'package:smartreceipt/presentation/screens/login_screen.dart';
import 'package:smartreceipt/presentation/screens/signup_screen.dart';
import 'package:smartreceipt/presentation/screens/onboarding_screen.dart';
import 'package:smartreceipt/presentation/screens/receipt_detail_screen.dart';
import 'package:smartreceipt/presentation/screens/scan_receipt_screen.dart';

class SmartReceiptApp extends ConsumerWidget {
  const SmartReceiptApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      // Use `home` for the main screen and `onGenerateRoute` for all other routes.
      // This is a more robust pattern than using `initialRoute` with `onGenerateRoute`.
      home: const HomeScreen(),
      onGenerateRoute: (RouteSettings settings) {
        print("Navigating to: ${settings.name}");
        switch (settings.name) {
          case AppRoutes.onboarding:
            return MaterialPageRoute(builder: (_) => const OnboardingScreen());
          case AppRoutes.home:
            return MaterialPageRoute(builder: (_) => const HomeScreen());
          case AppRoutes.login:
            return MaterialPageRoute(builder: (_) => const LoginScreen());
          case AppRoutes.signup:
            return MaterialPageRoute(builder: (_) => const SignupScreen());
          case AppRoutes.addReceipt:
            return MaterialPageRoute(builder: (_) => const AddReceiptScreen());
          case AppRoutes.scanReceipt:
            return MaterialPageRoute(builder: (_) => const ScanReceiptScreen());
          case AppRoutes.receiptDetail:
            // final args = settings.arguments; // This is how you would get arguments
            return MaterialPageRoute(builder: (_) => ReceiptDetailScreen());
          default:
            // Handle unknown routes
            return MaterialPageRoute(
                builder: (_) => Scaffold(body: Center(child: Text('No route defined for ${settings.name}'))));
        }
      },
    );
  }
}
