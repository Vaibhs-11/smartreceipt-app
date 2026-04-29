import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/core/utils/app_logger.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/home_screen.dart';
import 'package:receiptnest/presentation/screens/login_screen.dart';
import 'package:receiptnest/presentation/widgets/account_gate.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          AppLogger.log('No user logged in');
          return const LoginScreen();
        } else {
          AppLogger.log('User logged in');
          return const AccountGate(child: HomeScreen());
        }
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) {
        AppLogger.error('AuthGate error: $err');
        return const LoginScreen();
      },
    );
  }
}
