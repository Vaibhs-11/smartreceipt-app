import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/login_screen.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';
import 'package:smartreceipt/presentation/screens/receipt_detail_screen.dart';
import 'package:smartreceipt/presentation/screens/add_receipt_screen.dart';
import 'package:smartreceipt/presentation/screens/onboarding_screen.dart';
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
      // Proceed without env; AppConfig will use safe defaults via maybeGet
    }
  }

  // Initialize Firebase
  await Firebase.initializeApp();
  // Log the project ID to confirm the app is connecting to the correct Firebase project.
  // You can then check this project's Firestore region in the Firebase Console.
  debugPrint(
      "Firebase Initialized for project: ${Firebase.app().options.projectId}");

  runApp(const ProviderScope(child: SmartReceiptApp()));
}

class SmartReceiptApp extends ConsumerWidget {
  const SmartReceiptApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Using AuthGate to determine the initial screen is a robust way
    // to handle user authentication state.
    return MaterialApp(
      title: 'SmartReceipt',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthGate(),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    // Using debugPrint is better as it's a no-op in release builds.
    debugPrint("Navigating to: ${settings.name}");

    switch (settings.name) {
      case AppRoutes.onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case AppRoutes.signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
      case AppRoutes.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case AppRoutes.addReceipt:
        return MaterialPageRoute(builder: (_) => const AddReceiptScreen());
      case AppRoutes.scanReceipt:
        return MaterialPageRoute(builder: (_) => const ScanReceiptScreen());
      case AppRoutes.receiptDetail:
        // It's best practice to handle arguments safely.
        final receiptId = settings.arguments as String?;
        if (receiptId != null) {
          // You will need to update ReceiptDetailScreen to accept this parameter.
          return MaterialPageRoute(
              builder: (_) => ReceiptDetailScreen(receiptId: receiptId));
        }
        // Fallback or error case if the ID is missing.
        return _errorRoute();
      default:
        return _errorRoute("Route not found");
    }
  }

  Route<dynamic> _errorRoute([String message = "Error: Route not found"]) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(message)),
      ),
    );
  }
}
