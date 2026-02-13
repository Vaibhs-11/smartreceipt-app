import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/domain/services/subscription_service.dart';
import 'package:receiptnest/core/firebase/crashlytics_logger.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/routes/app_routes.dart';
import 'package:receiptnest/presentation/screens/home_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  static const String _billingUnavailableMessage =
      'Purchases are currently unavailable. Please try again later.';
  bool _processing = false;
  bool _loading = true;
  String? _message;
  List<ProductDetails> _products = <ProductDetails>[];
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  void initState() {
    super.initState();
    final subscriptionService = ref.read(subscriptionServiceProvider);
    _subscription = subscriptionService.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        CrashlyticsLogger.recordNonFatal(
          reason: 'BILLING_PURCHASE_STREAM_ERROR',
          error: error,
          context: {'operation': 'purchaseStream'},
        );
        if (!mounted) return;
        setState(() {
          _message = _billingUnavailableMessage;
        });
      },
    );
    _loadProducts();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Upgrade to Premium'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              platform == TargetPlatform.iOS
                  ? 'Premium keeps unlimited receipts. Prices shown are from the App Store.'
                  : 'Premium keeps unlimited receipts. Prices shown are from Google Play.',
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_products.isEmpty)
              const Text('Subscriptions are not available right now.')
            else
              for (final product in _products)
                _planTile(
                  title: _labelForProduct(product),
                  price: product.price,
                  description: product.description,
                  onPressed: () => _purchase(product),
                ),
            const SizedBox(height: 12),
            if (_message != null)
              Text(
                _message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (_canExitPurchase()) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _exitToHome,
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _planTile({
    required String title,
    required String price,
    required String description,
    required VoidCallback onPressed,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text('$price · $description'),
        trailing: ElevatedButton(
          onPressed: _processing ? null : onPressed,
          child: Text(_processing ? 'Processing…' : 'Subscribe'),
        ),
      ),
    );
  }

  Future<void> _loadProducts() async {
    final subscriptionService = ref.read(subscriptionServiceProvider);
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final connectivity = ref.read(connectivityServiceProvider);
      if (!await ensureInternetConnection(context, connectivity)) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      final products = await subscriptionService.fetchProducts();
      products.sort((a, b) => a.price.compareTo(b.price));
      if (!mounted) return;
      setState(() {
        _products = products;
      });
    } catch (e) {
      await CrashlyticsLogger.recordNonFatal(
        reason: 'BILLING_PRODUCTS_LOAD_FAILED',
        error: e,
        context: {'operation': 'fetchProducts'},
      );
      if (!mounted) return;
      setState(() {
        _message = _billingUnavailableMessage;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _purchase(ProductDetails product) async {
    final subscriptionService = ref.read(subscriptionServiceProvider);
    setState(() {
      _processing = true;
      _message = null;
    });
    try {
      final connectivity = ref.read(connectivityServiceProvider);
      if (!await ensureInternetConnection(context, connectivity)) {
        if (mounted) {
          setState(() => _processing = false);
        }
        return;
      }
      await subscriptionService.purchase(product);
    } catch (e) {
      if (isNetworkException(e)) {
        if (mounted) {
          await showNoInternetDialog(context);
          setState(() => _processing = false);
        }
        return;
      }
      await CrashlyticsLogger.recordNonFatal(
        reason: 'BILLING_PURCHASE_FAILED',
        error: e,
        context: {'operation': 'purchase', 'productId': product.id},
      );
      if (!mounted) return;
      setState(() {
        _message = _billingUnavailableMessage;
        _processing = false;
      });
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    if (purchases.isEmpty) return;
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.error) {
        await CrashlyticsLogger.recordNonFatal(
          reason: 'BILLING_PURCHASE_STATUS_ERROR',
          error: purchase.error ?? StateError('Unknown purchase error'),
          context: {'productId': purchase.productID},
        );
        setState(() {
          _message = _billingUnavailableMessage;
          _processing = false;
        });
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        setState(() {
          _message = _billingUnavailableMessage;
          _processing = false;
        });
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _syncEntitlementAndExit();
      }

      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  Future<void> _syncEntitlementAndExit() async {
    final subscriptionService = ref.read(subscriptionServiceProvider);
    final userRepo = ref.read(userRepositoryProvider);
    try {
      final connectivity = ref.read(connectivityServiceProvider);
      if (!await ensureInternetConnection(context, connectivity)) {
        if (mounted) {
          setState(() => _processing = false);
        }
        return;
      }
      final profile = await userRepo.getCurrentUserProfile();
      if (profile != null) {
        final entitlement = await subscriptionService.getCurrentEntitlement();
        await userRepo.applySubscriptionEntitlement(
          entitlement,
          currentProfile: profile,
        );
      }
      ref.refresh(userProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: const RouteSettings(name: AppRoutes.home),
        ),
        (_) => false,
      );
    } catch (e) {
      if (isNetworkException(e)) {
        if (mounted) {
          await showNoInternetDialog(context);
          setState(() => _processing = false);
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _message = _billingUnavailableMessage;
        _processing = false;
      });
    }
  }

  bool _canExitPurchase() {
    return !_processing && (_products.isEmpty || _message != null);
  }

  void _exitToHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const HomeScreen(),
        settings: const RouteSettings(name: AppRoutes.home),
      ),
      (_) => false,
    );
  }

  String _labelForProduct(ProductDetails product) {
    final tier = SubscriptionProductIds.tierForProduct(product.id);
    if (tier == SubscriptionTier.monthly) return 'Monthly';
    if (tier == SubscriptionTier.yearly) return 'Yearly';
    return product.title;
  }
}
