import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartreceipt/data/services/auth/firebase_auth_service.dart';
import 'package:smartreceipt/presentation/screens/login_screen.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';
import 'package:smartreceipt/presentation/screens/receipt_list_screen.dart';

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
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          // User is logged in
          print("User logged in with UID: ${snapshot.data!.uid}");
          return const HomeScreen();
        } else {
          // User not logged in
          print("No user logged in, redirecting to LoginScreen.");
          return const LoginScreen();
        }
      },
    );
  }
}
