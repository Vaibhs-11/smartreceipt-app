import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';
import 'package:smartreceipt/presentation/screens/login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
          debugPrint("✅ User logged in with UID: ${snapshot.data!.uid}");
          return const HomeScreen();
        } else {
          // User not logged in
          debugPrint("❌ No user logged in, redirecting to LoginScreen.");
          return const LoginScreen();
        }
      },
    );
  }
}
