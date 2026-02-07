import 'package:meta/meta.dart';

enum SubscriptionTier { free, monthly, yearly }

extension SubscriptionTierX on SubscriptionTier {
  String get asString {
    switch (this) {
      case SubscriptionTier.monthly:
        return 'monthly';
      case SubscriptionTier.yearly:
        return 'yearly';
      case SubscriptionTier.free:
      default:
        return 'free';
    }
  }

  static SubscriptionTier fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'monthly':
        return SubscriptionTier.monthly;
      case 'yearly':
        return SubscriptionTier.yearly;
      case 'free':
      default:
        return SubscriptionTier.free;
    }
  }

  bool get isPaid => this != SubscriptionTier.free;

}

enum SubscriptionStatus { active, expired, none }

extension SubscriptionStatusX on SubscriptionStatus {
  String get asString {
    switch (this) {
      case SubscriptionStatus.active:
        return 'active';
      case SubscriptionStatus.expired:
        return 'expired';
      case SubscriptionStatus.none:
      default:
        return 'none';
    }
  }

  static SubscriptionStatus fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'active':
        return SubscriptionStatus.active;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'none':
      default:
        return SubscriptionStatus.none;
    }
  }
}

enum SubscriptionSource { apple, google }

extension SubscriptionSourceX on SubscriptionSource {
  String get asString {
    switch (this) {
      case SubscriptionSource.apple:
        return 'apple';
      case SubscriptionSource.google:
        return 'google';
    }
  }

  static SubscriptionSource? fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'apple':
        return SubscriptionSource.apple;
      case 'google':
        return SubscriptionSource.google;
      default:
        return null;
    }
  }
}

@immutable
class SubscriptionEntitlement {
  const SubscriptionEntitlement({
    required this.tier,
    required this.status,
    this.source,
    this.updatedAt,
  });

  final SubscriptionTier tier;
  final SubscriptionStatus status;
  final SubscriptionSource? source;
  final DateTime? updatedAt;

  bool get isActive => status == SubscriptionStatus.active && tier.isPaid;
}
