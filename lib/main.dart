import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/onboarding_screen.dart';
import 'package:smartreceipt/presentation/screens/receipt_detail_screen.dart';
import 'package:smartreceipt/presentation/screens/add_receipt_screen.dart';
import 'package:smartreceipt/presentation/screens/scan_receipt_screen.dart';
import 'package:smartreceipt/presentation/screens/signup_screen.dart';
import 'package:smartreceipt/presentation/widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: 'config/.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'config/env.example');
    } catch (_) {
      // Proceed without env; runtime will rely on Firebase defaults
    }
  }

  // Initialize Firebase with options from firebase_options.dart
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint(
    "✅ Firebase Initialized for project: ${Firebase.app().options.projectId}",
  );

  runApp(
    const ProviderScope(
      child: SmartReceiptApp(),
    ),
  );
}

class SmartReceiptApp extends ConsumerWidget {
  const SmartReceiptApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'SmartReceipt',
      theme: ThemeData(primarySwatch: Colors.blue),
      
      // AuthGate controls ALL login/logout navigation
      home: AuthGate(),   // (❌ removed const)
      
      // Only sub-screens belong here
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    debugPrint("Navigating to: ${settings.name}");

    switch (settings.name) {
      case AppRoutes.onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());

      case AppRoutes.signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());

      case AppRoutes.addReceipt:
        return MaterialPageRoute(builder: (_) => const AddReceiptScreen());

      case AppRoutes.scanReceipt:
        return MaterialPageRoute(builder: (_) => const ScanReceiptScreen());

      case AppRoutes.receiptDetail:
        final receiptId = settings.arguments as String?;
        if (receiptId != null) {
          return MaterialPageRoute(
            builder: (_) => ReceiptDetailScreen(receiptId: receiptId),
          );
        }
        return _errorRoute("Missing receiptId");

      // ❌ Removed AppRoutes.login
      // ❌ Removed AppRoutes.home
      // These are now handled *exclusively* by AuthGate.

      default:
        return _errorRoute("Route not found");
    }
  }

  Route<dynamic> _errorRoute([String message = "Error"]) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(message)),
      ),
    );
  }
}
