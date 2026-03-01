import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/firebase/app_check_initializer.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'presentation/routes/app_routes.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/signup_screen.dart';
import 'presentation/screens/add_receipt_screen.dart';
import 'presentation/screens/scan_receipt_screen.dart';
import 'presentation/screens/receipt_detail_screen.dart';
import 'presentation/screens/trial_ended_gate_screen.dart';
import 'presentation/screens/keep3_selection_screen.dart';
import 'presentation/screens/purchase_screen.dart';
import 'presentation/screens/account_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/widgets/account_gate.dart';
import 'presentation/providers/providers.dart';
import 'presentation/utils/root_scaffold_messenger.dart'
    as root_scaffold_messenger;
import 'core/constants/app_constants.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    root_scaffold_messenger.rootScaffoldMessengerKey;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: 'config/.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'config/env.example');
    } catch (_) {}
  }

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Required so Crashlytics logs appear in Play Store release builds.
  FlutterError.onError =
      FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(true);

  await AppCheckInitializer.initialize();

  debugPrint(
    '✅ Firebase initialized: ${Firebase.app().options.projectId}',
  );

  runApp(
    const ProviderScope(
      child: SmartReceiptApp(),
    ),
  );
}

class SmartReceiptApp extends ConsumerStatefulWidget {
  const SmartReceiptApp({super.key});

  @override
  ConsumerState<SmartReceiptApp> createState() => _SmartReceiptAppState();
}

class _SmartReceiptAppState extends ConsumerState<SmartReceiptApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (prev, next) {
      final previousUser = prev?.asData?.value;
      final nextUser = next.asData?.value;

      if (previousUser != null && nextUser == null) {
        ref.refresh(userProfileProvider);
        ref.refresh(receiptCountProvider);
        ref.refresh(receiptsProvider);
      }
    });

    final authState = ref.watch(authStateProvider);
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: AppTheme.lightTheme,
      home: authState.when(
        data: (user) {
          if (user == null) {
            return const LoginScreen();
          }
          return const AccountGate(child: HomeScreen());
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const LoginScreen(),
      ),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case AppRoutes.signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
      case AppRoutes.addReceipt:
        final args = settings.arguments as AddReceiptScreenArgs?;
        return MaterialPageRoute(
          builder: (_) => AddReceiptScreen(
            initialImagePath: args?.initialImagePath,
            initialAction: args?.initialAction,
          ),
        );
      case AppRoutes.scanReceipt:
        return MaterialPageRoute(builder: (_) => const ScanReceiptScreen());
      case AppRoutes.receiptDetail:
        final receiptId = settings.arguments as String?;
        if (receiptId != null) {
          return MaterialPageRoute(
            builder: (_) => ReceiptDetailScreen(receiptId: receiptId),
          );
        }
        return _errorRoute('Missing receiptId');
      case AppRoutes.trialEndedGate:
        return MaterialPageRoute(
          builder: (_) => TrialEndedGateScreen(
            isSubscriptionEnded: settings.arguments as bool? ?? false,
            receiptCount: 0,
          ),
        );
      case AppRoutes.keep3Selection:
        return MaterialPageRoute(
          builder: (_) => Keep3SelectionScreen(
            isSubscriptionEnded: settings.arguments as bool? ?? false,
          ),
        );
      case AppRoutes.purchase:
        return MaterialPageRoute(builder: (_) => const PurchaseScreen());
      case AppRoutes.account:
        return MaterialPageRoute(builder: (_) => const AccountScreen());
      default:
        return _errorRoute('Route not found');
    }
  }

  Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(message)),
      ),
    );
  }
}
