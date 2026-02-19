import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:receiptnest/data/services/auth/auth_service.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb_auth.FirebaseAuth? instance})
      : _auth = instance ?? fb_auth.FirebaseAuth.instance;

  final fb_auth.FirebaseAuth _auth;

  final _firestore = FirebaseFirestore.instance;

  AppUser? _mapUser(fb_auth.User? user) =>
      user == null ? null : AppUser(uid: user.uid, email: user.email);

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.authStateChanges().map(_mapUser);
  }

  @override
  Future<AppUser?> signInAnonymously() async {
    if (_auth.currentUser != null) {
      return _mapUser(_auth.currentUser);
    }

    final fb_auth.UserCredential cred = await _auth.signInAnonymously();

    // also make sure we create a user doc for anonymous sign-in
    await _firestore.collection("users").doc(cred.user!.uid).set({
      "uid": cred.user!.uid,
      "email": cred.user!.email,
      "createdAt": FieldValue.serverTimestamp(),
      "isAnonymous": true,
      "accountStatus": "free",
      "trialDowngradeRequired": false,
      "trialUsed": false,
      "subscriptionTier": "free",
      "subscriptionStatus": "none",
    }, SetOptions(merge: true));

    return _mapUser(cred.user);
  }

  @override
  Future<AppUser?> signInWithEmailAndPassword(
      String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return _mapUser(cred.user);
  }

  @override
  Future<AppUser?> createUserWithEmailAndPassword(
      String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Create a Firestore user doc at the same time
    await _firestore.collection("users").doc(cred.user!.uid).set({
      "uid": cred.user!.uid,
      "email": cred.user!.email,
      "createdAt": FieldValue.serverTimestamp(),
      "isAnonymous": false,
      "accountStatus": "free",
      "trialDowngradeRequired": false,
      "trialUsed": false,
      "subscriptionTier": "free",
      "subscriptionStatus": "none",
    }, SetOptions(merge: true));

    return _mapUser(cred.user);
  }

  @override
  Future<void> signOut() {
    return _auth.signOut();
  }
}
