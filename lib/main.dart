import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/data/services/auth/firebase_auth_service.dart';
import 'package:smartreceipt/presentation/screens/login_screen.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';
import 'package:smartreceipt/presentation/screens/receipt_list_screen.dart';
import 'package:smartreceipt/presentation/screens/add_receipt_screen.dart';
import 'package:smartreceipt/presentation/screens/onboarding_screen.dart';
import 'package:smartreceipt/presentation/screens/scan_receipt_screen.dart';
import 'package:smartreceipt/presentation/widgets/auth_gate.dart';
import 'package:smartreceipt/presentation/app.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: 'config/.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'config/env.example');
    } catch (_) {
      // Proceed without env; AppConfig will use safe defaults via maybeGet
    }
  }

  // Initialize Firebase
  await Firebase.initializeApp();

  runApp(const ProviderScope(child: SmartReceiptApp()));
}

class SmartReceiptApp extends StatelessWidget {
  const SmartReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartReceipt',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: AppRoutes.login, // 👈 start with onboarding/auth gate
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    print("Navigating to: ${settings.name}"); // 👈 debug log

    switch (settings.name) {
      case AppRoutes.onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case AppRoutes.signup:
        return MaterialPageRoute(builder: (_) => const LoginScreen()); // Replace with SignupScreen
      case AppRoutes.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case AppRoutes.addReceipt:
        return MaterialPageRoute(builder: (_) => const AddReceiptScreen());
      case AppRoutes.scanReceipt:
        return MaterialPageRoute(builder: (_) => const ReceiptListScreen()); // Replace with ScanReceiptScreen
      case AppRoutes.receiptDetail:
        return MaterialPageRoute(builder: (_) => const ReceiptListScreen()); // Replace with ReceiptDetailScreen
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text("Route not found")),
          ),
        );
    }
  }
}