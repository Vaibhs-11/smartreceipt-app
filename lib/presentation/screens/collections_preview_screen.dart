import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/domain/policies/account_policies.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/create_collection_screen.dart';
import 'package:receiptnest/presentation/screens/purchase_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';
import 'package:receiptnest/presentation/utils/root_scaffold_messenger.dart';

class CollectionsPreviewScreen extends ConsumerStatefulWidget {
  const CollectionsPreviewScreen({super.key});

  @override
  ConsumerState<CollectionsPreviewScreen> createState() =>
      _CollectionsPreviewScreenState();
}

class _CollectionsPreviewScreenState
    extends ConsumerState<CollectionsPreviewScreen> {
  bool _startingTrial = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trips & Events',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryNavy,
          ),
        ),
      ),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Failed to load Trips & Events: $error')),
          data: (profile) {
            if (profile == null) {
              return const SizedBox.shrink();
            }

            final eligibility = AccountPolicies.evaluate(
              profile,
              DateTime.now().toUtc(),
            );
            final isPaidUser =
                profile.accountStatus == AccountStatus.paid ||
                profile.subscriptionStatus == SubscriptionStatus.active;
            final canStartTrial = !profile.trialUsed && !isPaidUser;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primaryNavy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.folder_copy_outlined,
                          size: 36,
                          color: AppColors.primaryNavy,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Turn your receipts into ready-to-use reports',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Group, track, and manage receipts for trips, work, and tax — all in one place.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _CollectionsPreviewBullet(
                    text: 'Track spending across trips and projects',
                  ),
                  const _CollectionsPreviewBullet(
                    text: 'Keep personal and work expenses organised',
                  ),
                  const _CollectionsPreviewBullet(
                    text: 'Get insights into where your money goes',
                  ),
                  const _CollectionsPreviewBullet(
                    text: 'Access everything in one place, anytime',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    canStartTrial
                        ? 'Start your free trial to unlock insights, trips, and unlimited organisation.'
                        : _upgradeMessage(profile),
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canStartTrial ? _startTrial : _openPurchase,
                      child: _startingTrial
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              canStartTrial
                                  ? 'Start Free Trial'
                                  : 'Upgrade for less than the cost of a cup of coffee each month',
                            ),
                    ),
                  ),
                  if (canStartTrial) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: _openPurchase,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryNavy,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        child: Text(_purchaseButtonLabel()),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _upgradeMessage(AppUserProfile profile) {
    if (profile.trialUsed == true) {
      return 'Upgrade to unlock insights, trips, and unlimited organisation.';
    }
    return 'Start your free trial to unlock insights, trips, and unlimited organisation.';
  }

  String _purchaseButtonLabel() {
    return 'Upgrade for less than the cost of a cup of coffee each month';
  }

  Future<void> _startTrial() async {
    if (_startingTrial) return;
    setState(() => _startingTrial = true);
    try {
      final connectivity = ref.read(connectivityServiceProvider);
      if (!await ensureInternetConnection(context, connectivity)) return;
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.startTrial();
      await ref.read(userProfileStreamProvider.stream).firstWhere(
        (profile) =>
            profile != null &&
            AccountPolicies.evaluate(profile, DateTime.now().toUtc())
                .isPremiumEligible,
      );
      if (!mounted) return;
      showRootSnackBar(
        const SnackBar(content: Text('Trial started')),
      );
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => const CreateCollectionScreen(),
        ),
      );
    } catch (e) {
      if (isNetworkException(e)) {
        if (mounted) {
          await showNoInternetDialog(context);
        }
        return;
      }
      if (!mounted) return;
      showRootSnackBar(
        SnackBar(content: Text('Could not start trial: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _startingTrial = false);
      }
    }
  }

  void _openPurchase() {
    Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const PurchaseScreen(),
      ),
    ).then((result) async {
      if (result != true || !mounted) {
        return;
      }

      await ref.read(userProfileStreamProvider.stream).firstWhere(
        (profile) =>
            profile != null &&
            AccountPolicies.evaluate(profile, DateTime.now().toUtc())
                .isPremiumEligible,
      );
      if (!mounted) {
        return;
      }

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => const CreateCollectionScreen(),
        ),
      );
    });
  }
}

class _CollectionsPreviewBullet extends StatelessWidget {
  const _CollectionsPreviewBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_outline,
              size: 20,
              color: AppColors.primaryNavy,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
