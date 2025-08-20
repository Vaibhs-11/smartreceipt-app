import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:smartreceipt/data/services/auth/auth_service.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb_auth.FirebaseAuth? instance})
      : _auth = instance ?? fb_auth.FirebaseAuth.instance;

  final fb_auth.FirebaseAuth _auth;

  AppUser? _mapUser(fb_auth.User? user) =>
      user == null ? null : AppUser(uid: user.uid, email: user.email);

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.authStateChanges().map(_mapUser);
  }

  @override
  Future<AppUser?> signInAnonymously() async {
    final fb_auth.UserCredential cred = await _auth.signInAnonymously();
    return _mapUser(cred.user);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

