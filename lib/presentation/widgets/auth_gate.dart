import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';
import 'package:smartreceipt/presentation/screens/login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          debugPrint("❌ No user logged in → LoginScreen");
          return const LoginScreen();
        } else {
          debugPrint("✅ User logged in → HomeScreen (uid: ${user.uid})");
          return const HomeScreen();
        }
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) {
        debugPrint("⚠️ AuthGate error: $err");
        return const LoginScreen();
      },
    );
  }
}
