import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/domain/exceptions/trial_exception.dart';
import 'package:receiptnest/domain/repositories/user_repository.dart';

class FirebaseUserRepository implements UserRepository {
  FirebaseUserRepository(
      {FirebaseAuth? authInstance,
      FirebaseFirestore? firestoreInstance,
      FirebaseFunctions? functionsInstance})
      : _auth = authInstance ?? FirebaseAuth.instance,
        _firestore = firestoreInstance ?? FirebaseFirestore.instance,
        _functions = functionsInstance ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  String? _uid() {
    return _auth.currentUser?.uid;
  }

  Future<AppUserProfile> _mapSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (snapshot.exists) {
      return AppUserProfile.fromFirestore(snapshot);
    }

    final uid = snapshot.id;
    final user = _auth.currentUser;
    final seedData = <String, Object?>{
      'uid': uid,
      'email': user?.email,
      'isAnonymous': user?.isAnonymous ?? true,
      'createdAt': FieldValue.serverTimestamp(),
      'trialDowngradeRequired': false,
    };

    await snapshot.reference.set(seedData, SetOptions(merge: true));
    final seededSnapshot = await snapshot.reference.get();
    return AppUserProfile.fromFirestore(seededSnapshot);
  }

  @override
  Future<AppUserProfile?> getCurrentUserProfile() async {
    final uid = _uid();
    if (uid == null) {
      return null;
    }
    final snapshot = await _userDoc(uid).get();
    return _mapSnapshot(snapshot);
  }

  @override
  Future<void> startTrial() async {
    final uid = _uid();
    if (uid == null) {
      debugPrint('Skipping startTrial: user not logged in.');
      return;
    }
    try {
      final HttpsCallable callable = _functions.httpsCallable('startTrial');
      await callable.call<Map<String, dynamic>>(const <String, dynamic>{});
    } on FirebaseFunctionsException catch (e, stackTrace) {
      debugPrint(
        'startTrial callable failed (code: ${e.code}, message: ${e.message})',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (e.code == 'failed-precondition') {
        throw const TrialAlreadyUsedException();
      }
      rethrow;
    }
  }

  @override
  Future<void> applySubscriptionEntitlement(
    SubscriptionEntitlement entitlement, {
    AppUserProfile? currentProfile,
  }) async {
    final uid = _uid();
    if (uid == null) {
      debugPrint('Skipping applySubscriptionEntitlement: user not logged in.');
      return;
    }

    final isCurrentPaidActive = currentProfile != null &&
        currentProfile.subscriptionStatus == SubscriptionStatus.active &&
        currentProfile.subscriptionTier.isPaid;

    if (entitlement.status == SubscriptionStatus.none && isCurrentPaidActive) {
      return;
    }

    final HttpsCallable callable =
        _functions.httpsCallable('syncSubscriptionEntitlement');
    await callable.call<Map<String, dynamic>>(<String, Object?>{
      'tier': entitlement.tier.asString,
      'status': entitlement.status.asString,
      'source': (entitlement.source ?? currentProfile?.subscriptionSource)
          ?.asString,
      'updatedAtMillis':
          (entitlement.updatedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> markDowngradeRequired() async {
    final uid = _uid();
    if (uid == null) {
      debugPrint('Skipping markDowngradeRequired: user not logged in.');
      return;
    }
    await _userDoc(uid).set(
      {
        'trialDowngradeRequired': true,
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> clearDowngradeRequired() async {
    final uid = _uid();
    if (uid == null) {
      debugPrint('Skipping clearDowngradeRequired: user not logged in.');
      return;
    }
    await _userDoc(uid).set(
      {
        'trialDowngradeRequired': false,
      },
      SetOptions(merge: true),
    );
  }
}
