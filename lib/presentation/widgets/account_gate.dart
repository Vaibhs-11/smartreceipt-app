import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/domain/policies/account_policies.dart';
import 'package:smartreceipt/domain/services/subscription_service.dart';
import 'package:smartreceipt/presentation/providers/app_config_provider.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/trial_ended_gate_screen.dart';

/// Observes lifecycle and enforces account gates on app start/resume.
class AccountGate extends ConsumerStatefulWidget {
  const AccountGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends ConsumerState<AccountGate>
    with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkGate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkGate();
    }
  }

  Future<void> _checkGate() async {
    if (_checking) return;
    _checking = true;
    try {
      final uid = ref.read(currentUidProvider);
      if (uid == null) {
        return;
      }
      final userRepo = ref.read(userRepositoryProvider);
      final receiptRepo = ref.read(receiptRepositoryProviderOverride);
      final subscriptionService = ref.read(subscriptionServiceProvider);
      final now = DateTime.now().toUtc();
      final appConfig = await ref.read(appConfigProvider.future);

      final profile = await userRepo.getCurrentUserProfile();
      if (profile == null) {
        return;
      }
      try {
        final entitlement = await subscriptionService.getCurrentEntitlement();
        await userRepo.applySubscriptionEntitlement(
          entitlement,
          currentProfile: profile,
        );
      } catch (e) {
        debugPrint('Subscription sync failed: $e');
      }

      final refreshedProfile = await userRepo.getCurrentUserProfile();
      if (refreshedProfile == null) {
        return;
      }
      final receiptCount = await receiptRepo.getReceiptCount();

      final trialExpired = refreshedProfile.trialEndsAt != null &&
          now.isAfter(refreshedProfile.trialEndsAt!);
      final subscriptionExpired = AccountPolicies.isSubscriptionExpired(
        refreshedProfile,
      );

      if ((trialExpired || subscriptionExpired) &&
          receiptCount <= appConfig.freeReceiptLimit) {
        await userRepo.clearDowngradeRequired();
      } else if ((trialExpired || subscriptionExpired) &&
          receiptCount > appConfig.freeReceiptLimit) {
        await userRepo.markDowngradeRequired();
      }

      final needsGate = AccountPolicies.downgradeRequired(
        refreshedProfile,
        receiptCount,
        now,
        appConfig,
      );

      if (needsGate && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => TrialEndedGateScreen(
              isSubscriptionEnded: subscriptionExpired,
              receiptCount: receiptCount,
            ),
            settings: const RouteSettings(name: AppRoutes.trialEndedGate),
          ),
          (_) => false,
        );
        return;
      }
    } catch (e) {
      debugPrint('Account gate check failed: $e');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
