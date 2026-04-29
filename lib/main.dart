import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/firebase/app_check_initializer.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
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
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/home_screen_router.dart';
import 'presentation/widgets/account_gate.dart';
import 'presentation/providers/providers.dart';
import 'presentation/utils/root_scaffold_messenger.dart'
    as root_scaffold_messenger;
import 'core/constants/app_constants.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    root_scaffold_messenger.rootScaffoldMessengerKey;
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

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
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

  await AppCheckInitializer.initialize();

  AppLogger.log('Firebase initialized');

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
  static const MethodChannel _shareChannel = MethodChannel('receiptnest/share');
  static const String _initialShareMethod = 'getInitialSharedFilePath';
  static const String _shareEventMethod = 'onSharedImage';

  StreamSubscription<List<SharedMediaFile>>? _intentSub;
  String? _pendingSharedImagePath;
  String? _lastHandledSharedImagePath;

  @override
  void initState() {
    super.initState();
    _configureNativeShareChannel();
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isEmpty) return;

      final sharedFiles = value;
      if (sharedFiles.length > 1) {
        _showError("Only one file can be imported at a time");
        return;
      }

      final file = File(sharedFiles.first.path);
      _handleSharedFile(file);
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isEmpty) return;

      final sharedFiles = value;
      if (sharedFiles.length > 1) {
        _showError("Only one file can be imported at a time");
        return;
      }

      final file = File(sharedFiles.first.path);
      _handleSharedFile(file);
    });
  }

  bool _isValidFile(File file) {
    final path = file.path.toLowerCase();

    if (!(path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.pdf'))) {
      return false;
    }

    final sizeInBytes = file.lengthSync();
    final sizeInMB = sizeInBytes / (1024 * 1024);

    return sizeInMB <= 10;
  }

  Future<void> _configureNativeShareChannel() async {
    _shareChannel.setMethodCallHandler(_handleNativeShareMethodCall);

    try {
      final initialPath = await _shareChannel.invokeMethod<String>(
        _initialShareMethod,
      );
      _queueSharedImagePath(initialPath);
    } catch (_) {}
  }

  Future<void> _handleNativeShareMethodCall(MethodCall call) async {
    if (call.method != _shareEventMethod) {
      return;
    }

    _queueSharedImagePath(call.arguments as String?);
  }

  void _queueSharedImagePath(String? path) {
    if (path == null || path.isEmpty) return;

    _pendingSharedImagePath = path;
    _handlePendingSharedImagePath();
  }

  void _handlePendingSharedImagePath() {
    final path = _pendingSharedImagePath;
    if (path == null || path.isEmpty) return;
    if (path == _lastHandledSharedImagePath) {
      _pendingSharedImagePath = null;
      return;
    }

    final file = File(path);
    if (!file.existsSync() || !_isValidFile(file)) {
      _pendingSharedImagePath = null;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) {
        Future<void>.delayed(
          const Duration(milliseconds: 300),
          _handlePendingSharedImagePath,
        );
        return;
      }

      _pendingSharedImagePath = null;
      _lastHandledSharedImagePath = path;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AddReceiptScreen(
            initialImagePath: path,
            initialFile: null,
            isFromShare: true,
          ),
        ),
      );
    });
  }

  void _handleSharedFile(File file) {
    if (!_isValidFile(file)) {
      _showError("Only images or PDFs under 10MB are supported");
      return;
    }

    if (!mounted) return;

    rootNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => AddReceiptScreen(
          initialImagePath: file.path,
          initialFile: null,
          isFromShare: true,
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;

    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
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
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: AppTheme.lightTheme,
      home: authState.when(
        data: (user) {
          if (user == null) {
            return const LoginScreen();
          }
          return const AccountGate(child: HomeScreenRouter());
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
            initialFile: null,
            isFromShare: false,
          ),
        );
      case AppRoutes.scanReceipt:
        return MaterialPageRoute(builder: (_) => const ScanReceiptScreen());
      case AppRoutes.receiptDetail:
        final args = settings.arguments;
        final receiptId = args is String
            ? args
            : args is Map
                ? args['receiptId']
                : null;
        final highlightCategory =
            args is Map ? args['highlightCategory'] as String? : null;
        final highlightItem =
            args is Map ? args['highlightItem'] as String? : null;
        if (receiptId is String) {
          return MaterialPageRoute(
            builder: (_) => ReceiptDetailScreen(
              receiptId: receiptId,
              highlightCategory: highlightCategory,
              highlightItem: highlightItem,
            ),
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
