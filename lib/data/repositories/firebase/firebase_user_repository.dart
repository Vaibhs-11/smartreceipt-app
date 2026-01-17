import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:smartreceipt/domain/entities/app_user.dart';
import 'package:smartreceipt/domain/entities/subscription_entitlement.dart';
import 'package:smartreceipt/domain/repositories/user_repository.dart';

class FirebaseUserRepository implements UserRepository {
  FirebaseUserRepository(
      {FirebaseAuth? authInstance, FirebaseFirestore? firestoreInstance})
      : _auth = authInstance ?? FirebaseAuth.instance,
        _firestore = firestoreInstance ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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
      final data = snapshot.data() ?? {};
      if (!data.containsKey('accountStatus') ||
          !data.containsKey('subscriptionTier') ||
          !data.containsKey('subscriptionStatus')) {
        await snapshot.reference.set({
          'accountStatus': AccountStatus.free.asString,
          'trialDowngradeRequired': false,
          'subscriptionTier': SubscriptionTier.free.asString,
          'subscriptionStatus': SubscriptionStatus.none.asString,
        }, SetOptions(merge: true));
      }
      return AppUserProfile.fromFirestore(snapshot);
    }

    final uid = snapshot.id;
    final user = _auth.currentUser;
    final seedData = <String, Object?>{
      'uid': uid,
      'email': user?.email,
      'isAnonymous': user?.isAnonymous ?? true,
      'createdAt': FieldValue.serverTimestamp(),
      'accountStatus': AccountStatus.free.asString,
      'trialDowngradeRequired': false,
      'subscriptionTier': SubscriptionTier.free.asString,
      'subscriptionStatus': SubscriptionStatus.none.asString,
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
    final now = DateTime.now().toUtc();
    final endsAt = now.add(const Duration(days: 7));

    await _userDoc(uid).set(
      {
        'accountStatus': AccountStatus.trial.asString,
        'trialStartedAt': Timestamp.fromDate(now),
        'trialEndsAt': Timestamp.fromDate(endsAt),
        'trialDowngradeRequired': false,
      },
      SetOptions(merge: true),
    );
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

    final payload = <String, Object?>{
      'subscriptionTier': entitlement.status == SubscriptionStatus.active
          ? entitlement.tier.asString
          : SubscriptionTier.free.asString,
      'subscriptionStatus': entitlement.status.asString,
      'subscriptionSource':
          (entitlement.source ?? currentProfile?.subscriptionSource)?.asString,
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    };

    await _userDoc(uid).set(payload, SetOptions(merge: true));
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
        'accountStatus': AccountStatus.free.asString,
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
        'accountStatus': AccountStatus.free.asString,
      },
      SetOptions(merge: true),
    );
  }
}
