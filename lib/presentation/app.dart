import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/core/constants/app_constants.dart';
import 'package:smartreceipt/core/theme/app_theme.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/add_receipt_screen.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';
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
      initialRoute: AppRoutes.home,
      routes: <String, WidgetBuilder>{
        AppRoutes.onboarding: (BuildContext context) => const OnboardingScreen(),
        AppRoutes.home: (BuildContext context) => const HomeScreen(),
        AppRoutes.addReceipt: (BuildContext context) => const AddReceiptScreen(),
        AppRoutes.scanReceipt: (BuildContext context) => const ScanReceiptScreen(),
        AppRoutes.receiptDetail: (BuildContext context) => const ReceiptDetailScreen(),
      },
    );
  }
}


