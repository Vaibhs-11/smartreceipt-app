import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

// Public model
class AppUser {
  const AppUser({required this.uid, this.email});
  final String uid;
  final String? email;
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  Future<AppUser?> signInAnonymously();
  Future<void> signOut();
}


//class FirebaseAuthService implements AuthService {
//  final FirebaseAuth _auth = FirebaseAuth.instance;
//
//  @override
//  Stream<AppUser?> authStateChanges() {
//    return _auth.authStateChanges().map((user) {
//      if (user == null) return null;
//      return AppUser(uid: user.uid, email: user.email);
//    });
//  }

//  @override
//  Future<AppUser?> signInAnonymously() async {
//    final cred = await _auth.signInAnonymously();
//    final u = cred.user;
//    if (u == null) return null;
//    return AppUser(uid: u.uid, email: u.email);
//    // Any errors will throw; optionally wrap in try/catch and surface a toast/snackbar
//  }

//  @override
//  Future<void> signOut() => _auth.signOut();
//}
