import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/presentation/providers/app_config_provider.dart';
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
  static final Uri _termsUri =
      Uri.parse('https://vaibhs-11.github.io/smartreceipt-legal/terms');
  static final Uri _privacyUri =
      Uri.parse('https://vaibhs-11.github.io/smartreceipt-legal/privacy.html');
  bool _processing = false;
  bool _loading = true;
  String? _message;
  List<ProductDetails> _products = <ProductDetails>[];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(subscriptionControllerProvider);
    final config = ref.watch(appConfigProvider).asData?.value;
    _processing = controller.busy || controller.hasUnconfirmedPurchase;
    final salesEnabled = config?.enablePaidTiers == true &&
        config?.enableSubscriptionPurchases == true;
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
            const Text(
              'Premium keeps unlimited receipts. Subscription pricing is shown below.',
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_products.isEmpty)
              const Text('Subscriptions are not available right now.')
            else if (!salesEnabled)
              const Text(
                  'New subscriptions are currently unavailable. Existing access is unchanged.')
            else
              for (final product in _products)
                _planTile(
                  title: _labelForProduct(product),
                  duration: _durationForProduct(product),
                  price: product.price,
                  description: product.description,
                  onPressed: () => _purchase(product),
                ),
            const SizedBox(height: 16),
            Text(
              'Payment will be charged at confirmation of purchase. '
              'Subscription renews automatically unless cancelled at least 24 hours before the end of the current period. '
              'Your account will be charged for renewal within 24 hours prior to the end of the current period.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: Wrap(
                spacing: 4,
                children: [
                  _footerLink(
                    context: context,
                    label: 'Terms of Use',
                    uri: _termsUri,
                  ),
                  Text(
                    '·',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _footerLink(
                    context: context,
                    label: 'Privacy Policy',
                    uri: _privacyUri,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (controller.message != null || _message != null)
              Text(
                controller.message ?? _message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (!controller.busy) ...[
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
    required String duration,
    required String price,
    required String description,
    required VoidCallback onPressed,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          '$duration · $price\nAuto-renews unless cancelled. $description',
        ),
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
      final config = await ref.read(appConfigProvider.future);
      if (!config.enablePaidTiers || !config.enableSubscriptionPurchases) {
        throw StateError('New subscriptions unavailable');
      }
      await ref.read(subscriptionControllerProvider).purchase(product);
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

  void _exitToHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
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

  String _durationForProduct(ProductDetails product) {
    final tier = SubscriptionProductIds.tierForProduct(product.id);
    if (tier == SubscriptionTier.monthly) return '1 month';
    if (tier == SubscriptionTier.yearly) return '1 year';
    return 'Auto-renewing';
  }

  Widget _footerLink({
    required BuildContext context,
    required String label,
    required Uri uri,
  }) {
    return TextButton(
      onPressed: () => _openExternalLink(uri),
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.underline,
            ),
      ),
    );
  }

  Future<void> _openExternalLink(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() {
        _message = 'Unable to open link right now. Please try again.';
      });
    }
  }
}
