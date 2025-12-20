import 'package:smartreceipt/domain/entities/app_user.dart';

class AccountPolicies {
  const AccountPolicies._();

  static bool isTrialActive(AppUserProfile user, DateTime nowUtc) {
    if (user.accountStatus != AccountStatus.trial) return false;
    final endsAt = user.trialEndsAt;
    if (endsAt == null) return true;
    return nowUtc.isBefore(endsAt);
  }

  static bool isPaidActive(AppUserProfile user, DateTime nowUtc) {
    if (user.accountStatus != AccountStatus.paid) return false;
    final endsAt = user.subscriptionEndsAt;
    if (endsAt == null) return true;
    return nowUtc.isBefore(endsAt);
  }

  static bool isExpired(AppUserProfile user, DateTime nowUtc) {
    final trialExpired = user.accountStatus == AccountStatus.trial &&
        user.trialEndsAt != null &&
        nowUtc.isAfter(user.trialEndsAt!);

    final paidExpired = user.accountStatus == AccountStatus.paid &&
        user.subscriptionEndsAt != null &&
        nowUtc.isAfter(user.subscriptionEndsAt!);

    return trialExpired || paidExpired;
  }

  static bool downgradeRequired(
    AppUserProfile user,
    int receiptCount,
    DateTime nowUtc,
  ) {
    if (user.trialDowngradeRequired) return true;
    if (!isExpired(user, nowUtc)) return false;
    return receiptCount > 3;
  }

  static bool canAddReceipt(
    AppUserProfile user,
    int receiptCount,
    DateTime nowUtc,
  ) {
    if (user.trialDowngradeRequired) return false;
    if (isPaidActive(user, nowUtc)) return true;
    if (isTrialActive(user, nowUtc)) return true;
    return receiptCount < 3;
  }
}
