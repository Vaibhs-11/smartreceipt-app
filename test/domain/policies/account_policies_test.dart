import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/domain/entities/app_config.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/domain/policies/account_policies.dart';

void main() {
  const config = AppConfig(
    freeReceiptLimit: 3,
    premiumReceiptLimit: -1,
    enablePaidTiers: true,
  );

  AppUserProfile buildUser({
    AccountStatus accountStatus = AccountStatus.free,
    SubscriptionTier subscriptionTier = SubscriptionTier.free,
    SubscriptionStatus subscriptionStatus = SubscriptionStatus.none,
    DateTime? trialEndsAt,
    bool trialUsed = false,
  }) {
    return AppUserProfile(
      uid: 'u1',
      email: 'test@example.com',
      isAnonymous: false,
      createdAt: DateTime.utc(2026, 1, 1),
      accountStatus: accountStatus,
      subscriptionTier: subscriptionTier,
      subscriptionStatus: subscriptionStatus,
      trialEndsAt: trialEndsAt,
      trialUsed: trialUsed,
    );
  }

  group('AccountPolicies.evaluate', () {
    test('sales disabled does not change free limits or trial access', () {
      expect(config.enableSubscriptionPurchases, false);
      final now = DateTime.utc(2026, 3, 1);
      expect(AccountPolicies.canAddReceipt(buildUser(), 2, now, config), true);
      expect(AccountPolicies.canAddReceipt(buildUser(), 3, now, config), false);
      final trial = buildUser(
          accountStatus: AccountStatus.trial,
          trialEndsAt: now.add(const Duration(days: 3)));
      expect(AccountPolicies.canAddReceipt(trial, 100, now, config), true);
    });

    test('expired subscription cannot override an active trial', () {
      final now = DateTime.utc(2026, 3, 1);
      final user = buildUser(
          accountStatus: AccountStatus.trial,
          subscriptionStatus: SubscriptionStatus.expired,
          trialEndsAt: now.add(const Duration(days: 3)));
      expect(AccountPolicies.isExpired(user, now), false);
      expect(AccountPolicies.downgradeRequired(user, 100, now, config), false);
      expect(AccountPolicies.canAddReceipt(user, 100, now, config), true);
    });

    test('known paid expiry is enforced while legacy null remains compatible',
        () {
      final now = DateTime.utc(2026, 3, 1);
      final legacy = buildUser(
          subscriptionTier: SubscriptionTier.monthly,
          subscriptionStatus: SubscriptionStatus.active);
      expect(AccountPolicies.isPaidActive(legacy, now), true);
      final expired = legacy.copyWith(subscriptionEndsAt: now);
      expect(AccountPolicies.isPaidActive(expired, now), false);
      expect(
          AccountPolicies.downgradeRequired(expired, 100, now, config), true);
    });

    test('paid access overrides stale downgrade gate', () {
      final now = DateTime.utc(2026, 3, 1);
      final user = buildUser(
              subscriptionTier: SubscriptionTier.yearly,
              subscriptionStatus: SubscriptionStatus.active)
          .copyWith(
              trialDowngradeRequired: true,
              subscriptionEndsAt: now.add(const Duration(days: 30)));
      expect(AccountPolicies.downgradeRequired(user, 100, now, config), false);
    });

    test('expired trial is treated as free and not premium-eligible', () {
      final now = DateTime.utc(2026, 3, 1);
      final user = buildUser(
        accountStatus: AccountStatus.trial,
        trialEndsAt: DateTime.utc(2026, 2, 25),
        trialUsed: true,
      );

      final eligibility = AccountPolicies.evaluate(user, now);

      expect(eligibility.effectiveState, EffectiveAccountState.free);
      expect(eligibility.isActiveTrial, isFalse);
      expect(eligibility.trialExpired, isTrue);
      expect(eligibility.trialDaysRemaining, 0);
      expect(eligibility.isPremiumEligible, isFalse);
      expect(AccountPolicies.canAddReceipt(user, 3, now, config), isFalse);
      expect(AccountPolicies.canAddReceipt(user, 2, now, config), isTrue);
    });

    test('active trial is premium-eligible and uses trial state', () {
      final now = DateTime.utc(2026, 3, 1);
      final user = buildUser(
        accountStatus: AccountStatus.trial,
        trialEndsAt: DateTime.utc(2026, 3, 5),
      );

      final eligibility = AccountPolicies.evaluate(user, now);

      expect(eligibility.effectiveState, EffectiveAccountState.trial);
      expect(eligibility.isActiveTrial, isTrue);
      expect(eligibility.trialExpired, isFalse);
      expect(eligibility.trialDaysRemaining, 4);
      expect(eligibility.isPremiumEligible, isTrue);
      expect(AccountPolicies.canAddReceipt(user, 100, now, config), isTrue);
    });

    test('paid user stays premium regardless of trial fields', () {
      final now = DateTime.utc(2026, 3, 1);
      final user = buildUser(
        accountStatus: AccountStatus.trial,
        subscriptionTier: SubscriptionTier.monthly,
        subscriptionStatus: SubscriptionStatus.active,
        trialEndsAt: DateTime.utc(2026, 2, 1),
      );

      final eligibility = AccountPolicies.evaluate(user, now);

      expect(eligibility.effectiveState, EffectiveAccountState.paid);
      expect(eligibility.isPaid, isTrue);
      expect(eligibility.isPremiumEligible, isTrue);
      expect(AccountPolicies.canAddReceipt(user, 100, now, config), isTrue);
    });

    test('free user with no trial data stays free', () {
      final now = DateTime.utc(2026, 3, 1);
      final user = buildUser();

      final eligibility = AccountPolicies.evaluate(user, now);

      expect(eligibility.effectiveState, EffectiveAccountState.free);
      expect(eligibility.isActiveTrial, isFalse);
      expect(eligibility.trialExpired, isFalse);
      expect(eligibility.trialDaysRemaining, 0);
      expect(eligibility.isPremiumEligible, isFalse);
    });
  });
}
