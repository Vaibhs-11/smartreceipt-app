import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';

enum AccountStatus { free, trial, paid }

extension AccountStatusX on AccountStatus {
  String get asString {
    switch (this) {
      case AccountStatus.free:
        return 'free';
      case AccountStatus.trial:
        return 'trial';
      case AccountStatus.paid:
        return 'paid';
    }
  }

  static AccountStatus fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'trial':
        return AccountStatus.trial;
      case 'paid':
        return AccountStatus.paid;
      case 'free':
      default:
        return AccountStatus.free;
    }
  }
}

@immutable
class AppUserProfile extends Equatable {
  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.isAnonymous,
    required this.createdAt,
    required this.accountStatus,
    required this.subscriptionTier,
    required this.subscriptionStatus,
    this.trialStartedAt,
    this.trialEndsAt,
    this.subscriptionEndsAt,
    this.trialDowngradeRequired = false,
    this.subscriptionSource,
    this.subscriptionUpdatedAt,
  });

  final String uid;
  final String? email;
  final bool isAnonymous;
  final DateTime? createdAt;
  final AccountStatus accountStatus;
  final SubscriptionTier subscriptionTier;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;
  final bool trialDowngradeRequired;
  final SubscriptionSource? subscriptionSource;
  final DateTime? subscriptionUpdatedAt;

  AppUserProfile copyWith({
    String? uid,
    String? email,
    bool? isAnonymous,
    DateTime? createdAt,
    AccountStatus? accountStatus,
    SubscriptionTier? subscriptionTier,
    SubscriptionStatus? subscriptionStatus,
    DateTime? trialStartedAt,
    DateTime? trialEndsAt,
    DateTime? subscriptionEndsAt,
    bool? trialDowngradeRequired,
    SubscriptionSource? subscriptionSource,
    DateTime? subscriptionUpdatedAt,
  }) {
    return AppUserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt ?? this.createdAt,
      accountStatus: accountStatus ?? this.accountStatus,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      subscriptionEndsAt: subscriptionEndsAt ?? this.subscriptionEndsAt,
      trialDowngradeRequired:
          trialDowngradeRequired ?? this.trialDowngradeRequired,
      subscriptionSource: subscriptionSource ?? this.subscriptionSource,
      subscriptionUpdatedAt: subscriptionUpdatedAt ?? this.subscriptionUpdatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'uid': uid,
      'email': email,
      'isAnonymous': isAnonymous,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'accountStatus': accountStatus.asString,
      'subscriptionTier': subscriptionTier.asString,
      'subscriptionStatus': subscriptionStatus.asString,
      'subscriptionSource': subscriptionSource?.asString,
      'subscriptionUpdatedAt': subscriptionUpdatedAt != null
          ? Timestamp.fromDate(subscriptionUpdatedAt!)
          : null,
      'trialStartedAt':
          trialStartedAt != null ? Timestamp.fromDate(trialStartedAt!) : null,
      'trialEndsAt':
          trialEndsAt != null ? Timestamp.fromDate(trialEndsAt!) : null,
      'subscriptionEndsAt': subscriptionEndsAt != null
          ? Timestamp.fromDate(subscriptionEndsAt!)
          : null,
      'trialDowngradeRequired': trialDowngradeRequired,
    };
  }

  factory AppUserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final accountStatus =
        AccountStatusX.fromString(data['accountStatus'] as String?);
    final subscriptionTier =
        SubscriptionTierX.fromString(data['subscriptionTier'] as String?);
    final subscriptionStatus =
        SubscriptionStatusX.fromString(data['subscriptionStatus'] as String?);

    return AppUserProfile(
      uid: data['uid'] as String? ?? doc.id,
      email: data['email'] as String?,
      isAnonymous: data['isAnonymous'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      accountStatus: accountStatus,
      subscriptionTier: subscriptionTier,
      subscriptionStatus: subscriptionStatus,
      trialStartedAt: (data['trialStartedAt'] as Timestamp?)?.toDate(),
      trialEndsAt: (data['trialEndsAt'] as Timestamp?)?.toDate(),
      subscriptionEndsAt:
          (data['subscriptionEndsAt'] as Timestamp?)?.toDate(),
      trialDowngradeRequired: data['trialDowngradeRequired'] as bool? ?? false,
      subscriptionSource:
          SubscriptionSourceX.fromString(data['subscriptionSource'] as String?),
      subscriptionUpdatedAt:
          (data['subscriptionUpdatedAt'] as Timestamp?)?.toDate(),
    );
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        isAnonymous,
        createdAt,
        accountStatus,
        subscriptionTier,
        subscriptionStatus,
        trialStartedAt,
        trialEndsAt,
        subscriptionEndsAt,
        trialDowngradeRequired,
        subscriptionSource,
        subscriptionUpdatedAt,
      ];
}
