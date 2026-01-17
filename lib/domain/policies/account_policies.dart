import 'package:smartreceipt/domain/entities/app_config.dart';
import 'package:smartreceipt/domain/entities/app_user.dart';
import 'package:smartreceipt/domain/entities/subscription_entitlement.dart';

class AccountPolicies {
  const AccountPolicies._();

  static bool isTrialActive(AppUserProfile user, DateTime nowUtc) {
    if (user.accountStatus != AccountStatus.trial) return false;
    final endsAt = user.trialEndsAt;
    if (endsAt == null) return true;
    return nowUtc.isBefore(endsAt);
  }

  static bool isPaidActive(AppUserProfile user, DateTime nowUtc) {
    return user.subscriptionStatus == SubscriptionStatus.active &&
        user.subscriptionTier.isPaid;
  }

  static bool isSubscriptionExpired(AppUserProfile user) {
    return user.subscriptionStatus == SubscriptionStatus.expired;
  }

  static bool isExpired(AppUserProfile user, DateTime nowUtc) {
    final trialExpired = user.accountStatus == AccountStatus.trial &&
        user.trialEndsAt != null &&
        nowUtc.isAfter(user.trialEndsAt!);

    final paidExpired = isSubscriptionExpired(user);

    return trialExpired || paidExpired;
  }

  static bool downgradeRequired(
    AppUserProfile user,
    int receiptCount,
    DateTime nowUtc,
    AppConfig config,
  ) {
    if (user.trialDowngradeRequired) return true;
    if (!isExpired(user, nowUtc)) return false;
    return receiptCount > config.freeReceiptLimit;
  }

  static bool canAddReceipt(
    AppUserProfile user,
    int receiptCount,
    DateTime nowUtc,
    AppConfig config,
  ) {
    if (user.trialDowngradeRequired) return false;
    if (config.enablePaidTiers && isPaidActive(user, nowUtc)) {
      return true;
    }
    if (config.enablePaidTiers && isTrialActive(user, nowUtc)) {
      return !_isPremiumLimitReached(receiptCount, config);
    }
    return receiptCount < config.freeReceiptLimit;
  }

  static bool _isPremiumLimitReached(int receiptCount, AppConfig config) {
    final limit = config.premiumReceiptLimit;
    if (limit == -1) return false;
    return receiptCount >= limit;
  }
}
