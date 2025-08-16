import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
  runApp(const ProviderScope(child: SmartReceiptApp()));
}

