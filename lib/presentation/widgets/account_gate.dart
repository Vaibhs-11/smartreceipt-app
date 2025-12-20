import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/domain/policies/account_policies.dart';
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
      final userRepo = ref.read(userRepositoryProvider);
      final receiptRepo = ref.read(receiptRepositoryProviderOverride);
      final now = DateTime.now().toUtc();

      final profile = await userRepo.getCurrentUserProfile();
      final receiptCount = await receiptRepo.getReceiptCount();

      final trialExpired =
          profile.trialEndsAt != null && now.isAfter(profile.trialEndsAt!);
      final subscriptionExpired = profile.subscriptionEndsAt != null &&
          now.isAfter(profile.subscriptionEndsAt!);

      if ((trialExpired || subscriptionExpired) && receiptCount <= 3) {
        await userRepo.clearDowngradeRequired();
      } else if ((trialExpired || subscriptionExpired) && receiptCount > 3) {
        await userRepo.markDowngradeRequired();
      }

      final refreshedProfile = await userRepo.getCurrentUserProfile();
      final needsGate = AccountPolicies.downgradeRequired(
        refreshedProfile,
        receiptCount,
        now,
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
