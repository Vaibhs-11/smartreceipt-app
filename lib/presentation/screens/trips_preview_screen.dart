import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/domain/policies/account_policies.dart';
import 'package:receiptnest/domain/services/subscription_service.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/create_trip_screen.dart';
import 'package:receiptnest/presentation/screens/purchase_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';
import 'package:receiptnest/presentation/utils/root_scaffold_messenger.dart';

class TripsPreviewScreen extends ConsumerStatefulWidget {
  const TripsPreviewScreen({super.key});

  @override
  ConsumerState<TripsPreviewScreen> createState() => _TripsPreviewScreenState();
}

class _TripsPreviewScreenState extends ConsumerState<TripsPreviewScreen> {
  bool _startingTrial = false;
  String? _monthlyPrice;

  @override
  void initState() {
    super.initState();
    _loadMonthlyPrice();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trips',
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
          error: (error, _) => Center(child: Text('Failed to load Trips: $error')),
          data: (profile) {
            if (profile == null) {
              return const SizedBox.shrink();
            }

            final eligibility = AccountPolicies.evaluate(
              profile,
              DateTime.now().toUtc(),
            );
            final canStartTrial =
                !eligibility.isPremiumEligible && profile.trialUsed != true;

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
                          Icons.luggage_outlined,
                          size: 36,
                          color: AppColors.primaryNavy,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Organise receipts by trip',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Keep travel receipts grouped together, track spend for each trip, and export a cleaner record when you need it.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _TripsPreviewBullet(
                    text: 'Create separate personal and work trips',
                  ),
                  const _TripsPreviewBullet(
                    text: 'See receipts and totals grouped in one place',
                  ),
                  const _TripsPreviewBullet(
                    text: 'Keep travel records ready for reporting and export',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    canStartTrial
                        ? 'Start your free trial to unlock Trips and other Premium features.'
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
                                  : 'Upgrade to Premium',
                            ),
                    ),
                  ),
                  if (canStartTrial) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _openPurchase,
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

  Future<void> _loadMonthlyPrice() async {
    try {
      final subscriptionService = ref.read(subscriptionServiceProvider);
      final products = await subscriptionService.fetchProducts();
      final ProductDetails? monthlyProduct = products.cast<ProductDetails?>().firstWhere(
            (product) =>
                product != null &&
                SubscriptionProductIds.tierForProduct(product.id) ==
                    SubscriptionTier.monthly,
            orElse: () => null,
          );
      if (!mounted || monthlyProduct == null) {
        return;
      }
      setState(() => _monthlyPrice = monthlyProduct.price);
    } catch (_) {
      // Leave pricing copy generic if billing metadata is unavailable.
    }
  }

  String _upgradeMessage(AppUserProfile profile) {
    final priceText = _monthlyPrice == null ? 'monthly pricing' : '${_monthlyPrice!} / month';
    if (profile.trialUsed == true) {
      return 'Upgrade to Premium to unlock Trips. Plans start at $priceText.';
    }
    return 'Unlock Trips with Premium. Plans start at $priceText, or start your free trial if available.';
  }

  String _purchaseButtonLabel() {
    return _monthlyPrice == null
        ? 'Upgrade to Premium'
        : 'Upgrade to Premium (${_monthlyPrice!} / month)';
  }

  Future<void> _startTrial() async {
    if (_startingTrial) return;
    setState(() => _startingTrial = true);
    try {
      final connectivity = ref.read(connectivityServiceProvider);
      if (!await ensureInternetConnection(context, connectivity)) return;
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.startTrial();
      await ref.refresh(userProfileProvider.future);
      if (!mounted) return;
      showRootSnackBar(
        const SnackBar(content: Text('Trial started')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const CreateTripScreen(),
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PurchaseScreen(),
      ),
    );
  }
}

class _TripsPreviewBullet extends StatelessWidget {
  const _TripsPreviewBullet({required this.text});

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
