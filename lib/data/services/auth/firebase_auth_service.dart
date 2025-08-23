import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb_auth.FirebaseAuth? instance})
      : _auth = instance ?? fb_auth.FirebaseAuth.instance;

  final fb_auth.FirebaseAuth _auth;
  static const String _uidKey = 'persisted_uid';
  AppUser? _mapUser(fb_auth.User? user) =>
      user == null ? null : AppUser(uid: user.uid, email: user.email);

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.authStateChanges().map(_mapUser);
  }

  @override
  Future<AppUser?> signInAnonymously() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if we already have a stored UID
    final storedUid = prefs.getString(_uidKey);
    if (storedUid != null) {
      print('[signInAnonymously] Using stored UID: $storedUid');
      // Return an AppUser with stored UID (simulate persistence)
      return AppUser(uid: storedUid, email: null);
    }
    final fb_auth.UserCredential cred = await _auth.signInAnonymously();
    final uid = cred.user?.uid;
    print('[signInAnonymously] New UID created: $uid');

    if (uid != null) {
      await prefs.setString(_uidKey, uid);
    }

    return _mapUser(cred.user);
  }

   @override
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_uidKey); // clear persisted UID on sign out
    return _auth.signOut();
  }
}

