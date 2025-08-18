import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartreceipt/presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: 'config/.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'config/env.example');
    } catch (_) {
      // Proceed without env; AppConfig will use safe defaults via maybeGet
    }
  }
  await Firebase.initializeApp();
  // Ensure an anonymous user is signed in so a unique uid is available
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
      print("No user logged in yet.");
    } else {
      print("User already logged in.");
      print("Current UID: ${FirebaseAuth.instance.currentUser?.uid}");
    }
  } catch (_) { 
    // If sign-in fails, the app can still run; HomeScreen provides manual sign-in
  }
  runApp(const ProviderScope(child: SmartReceiptApp()));
}

