import 'package:receiptnest/domain/entities/app_config.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';

enum EffectiveAccountState { free, trial, paid }

class AccountEligibility {
  const AccountEligibility({
    required this.effectiveState,
    required this.isPaid,
    required this.isActiveTrial,
    required this.isPremiumEligible,
    required this.trialDaysRemaining,
    required this.trialExpired,
  });

  final EffectiveAccountState effectiveState;
  final bool isPaid;
  final bool isActiveTrial;
  final bool isPremiumEligible;
  final int trialDaysRemaining;
  final bool trialExpired;
}

class AccountPolicies {
  const AccountPolicies._();

  static AccountEligibility evaluate(AppUserProfile user, DateTime nowUtc) {
    final isPaid = user.subscriptionStatus == SubscriptionStatus.active &&
        user.subscriptionTier.isPaid;

    final trialEndsAt = user.trialEndsAt;
    final isActiveTrial = !isPaid &&
        user.accountStatus == AccountStatus.trial &&
        trialEndsAt != null &&
        nowUtc.isBefore(trialEndsAt);
    final trialExpired = !isPaid &&
        user.accountStatus == AccountStatus.trial &&
        trialEndsAt != null &&
        !nowUtc.isBefore(trialEndsAt);

    final trialDaysRemaining = isActiveTrial
        ? trialEndsAt.difference(nowUtc).inDays.clamp(0, 999)
        : 0;

    final effectiveState = isPaid
        ? EffectiveAccountState.paid
        : isActiveTrial
            ? EffectiveAccountState.trial
            : EffectiveAccountState.free;

    return AccountEligibility(
      effectiveState: effectiveState,
      isPaid: isPaid,
      isActiveTrial: isActiveTrial,
      isPremiumEligible: isPaid || isActiveTrial,
      trialDaysRemaining: trialDaysRemaining,
      trialExpired: trialExpired,
    );
  }

  static bool isTrialActive(AppUserProfile user, DateTime nowUtc) {
    return evaluate(user, nowUtc).isActiveTrial;
  }

  static bool isPaidActive(AppUserProfile user, DateTime nowUtc) {
    return evaluate(user, nowUtc).isPaid;
  }

  static bool isSubscriptionExpired(AppUserProfile user) {
    return user.subscriptionStatus == SubscriptionStatus.expired;
  }

  static bool isExpired(AppUserProfile user, DateTime nowUtc) {
    final eligibility = evaluate(user, nowUtc);
    return eligibility.trialExpired || isSubscriptionExpired(user);
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
    final eligibility = evaluate(user, nowUtc);
    if (config.enablePaidTiers && eligibility.isPaid) {
      return true;
    }
    if (config.enablePaidTiers && eligibility.isActiveTrial) {
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
