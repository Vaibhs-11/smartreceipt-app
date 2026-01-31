import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:smartreceipt/domain/entities/subscription_entitlement.dart';
import 'package:smartreceipt/core/firebase/crashlytics_logger.dart';

abstract class SubscriptionService {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<SubscriptionEntitlement> getCurrentEntitlement();
  Future<void> restorePurchases();
  Future<List<ProductDetails>> fetchProducts();
  Future<void> purchase(ProductDetails product);
}

class SubscriptionProductIds {
  static Set<String> allIds() {
    final monthly = monthlyId();
    final yearly = yearlyId();
    if (monthly == null || yearly == null) {
      throw StateError('Missing subscription product IDs');
    }
    return {monthly, yearly};
  }

  static String? monthlyId() {
    if (Platform.isIOS) {
      return _envOrNull('IOS_SUBSCRIPTION_MONTHLY_ID');
    }
    if (Platform.isAndroid) {
      return _envOrNull('ANDROID_SUBSCRIPTION_MONTHLY_ID');
    }
    return null;
  }

  static String? yearlyId() {
    if (Platform.isIOS) {
      return _envOrNull('IOS_SUBSCRIPTION_YEARLY_ID');
    }
    if (Platform.isAndroid) {
      return _envOrNull('ANDROID_SUBSCRIPTION_YEARLY_ID');
    }
    return null;
  }

  static SubscriptionTier? tierForProduct(String productId) {
    final monthly = monthlyId();
    final yearly = yearlyId();
    if (productId == monthly) return SubscriptionTier.monthly;
    if (productId == yearly) return SubscriptionTier.yearly;
    return null;
  }

  static SubscriptionSource? platformSource() {
    if (Platform.isIOS) return SubscriptionSource.apple;
    if (Platform.isAndroid) return SubscriptionSource.google;
    return null;
  }

  static String? _envOrNull(String key) {
    final value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

class StoreSubscriptionService implements SubscriptionService {
  StoreSubscriptionService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  @override
  Future<List<ProductDetails>> fetchProducts() async {
    final ids = SubscriptionProductIds.allIds();
    await _ensureBillingReady(operation: 'fetchProducts');
    final response = await _inAppPurchase.queryProductDetails(ids);
    if (response.error != null) {
      await CrashlyticsLogger.recordNonFatal(
        reason: 'BILLING_PRODUCT_QUERY_FAILED',
        error: StateError(response.error!.message),
        context: {
          'operation': 'fetchProducts',
          'source': response.error!.source,
          'code': response.error!.code,
        },
      );
      throw StateError(response.error!.message);
    }
    if (response.productDetails.isEmpty) {
      await CrashlyticsLogger.recordNonFatal(
        reason: 'BILLING_PRODUCTS_EMPTY',
        error: StateError('No product details returned'),
        context: {
          'operation': 'fetchProducts',
          'requestedIds': ids.join(','),
        },
      );
    }
    return response.productDetails;
  }

  @override
  Future<void> purchase(ProductDetails product) async {
    await _ensureBillingReady(operation: 'purchase');
    if (product.id.trim().isEmpty) {
      await CrashlyticsLogger.recordNonFatal(
        reason: 'BILLING_INVALID_PRODUCT',
        error: StateError('ProductDetails is missing an id'),
        context: {'operation': 'purchase'},
      );
      throw StateError('Invalid product');
    }
    final param = PurchaseParam(productDetails: product);
    try {
      await _inAppPurchase.buyNonConsumable(purchaseParam: param);
    } catch (e, s) {
      await CrashlyticsLogger.recordNonFatal(
        reason: 'BILLING_LAUNCH_FAILED',
        error: e,
        stackTrace: s,
        context: {
          'operation': 'purchase',
          'productId': product.id,
        },
      );
      rethrow;
    }
  }

  @override
  Future<void> restorePurchases() async {
    await _ensureBillingReady(operation: 'restorePurchases');
    try {
      await _inAppPurchase.restorePurchases();
    } catch (e, s) {
      await CrashlyticsLogger.recordNonFatal(
        reason: 'BILLING_RESTORE_FAILED',
        error: e,
        stackTrace: s,
        context: {'operation': 'restorePurchases'},
      );
      rethrow;
    }
  }

  @override
  Future<SubscriptionEntitlement> getCurrentEntitlement() async {
    await _ensureBillingReady(operation: 'getCurrentEntitlement');

    final ids = SubscriptionProductIds.allIds();
    final pastPurchases = await _queryPastPurchasesSafe();
    final relevant = pastPurchases
        .where((purchase) => ids.contains(purchase.productID))
        .toList();

    if (relevant.isEmpty) {
      return SubscriptionEntitlement(
        tier: SubscriptionTier.free,
        status: SubscriptionStatus.none,
        source: SubscriptionProductIds.platformSource(),
        updatedAt: DateTime.now().toUtc(),
      );
    }

    PurchaseDetails? latestActive;
    for (final purchase in relevant) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        if (latestActive == null ||
            _purchaseTimestamp(purchase) > _purchaseTimestamp(latestActive)) {
          latestActive = purchase;
        }
      }
    }

      if (latestActive != null) {
      final tier = SubscriptionProductIds.tierForProduct(latestActive.productID) ??
          SubscriptionTier.free;
      return SubscriptionEntitlement(
        tier: tier,
        status: SubscriptionStatus.active,
        source: SubscriptionProductIds.platformSource(),
        updatedAt: DateTime.now().toUtc(),
      );
    }

    final hasCanceled = relevant.any(
      (purchase) => purchase.status == PurchaseStatus.canceled,
    );
    return SubscriptionEntitlement(
      tier: SubscriptionTier.free,
      status: hasCanceled ? SubscriptionStatus.expired : SubscriptionStatus.none,
      source: SubscriptionProductIds.platformSource(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<List<PurchaseDetails>> _queryPastPurchasesSafe() async {
    try {
      final dynamic api = _inAppPurchase;
      final dynamic response = await api.queryPastPurchases();
      final Object? error = response.error;
      if (error != null) {
        final message = (error as dynamic).message;
        throw StateError(message?.toString() ?? error.toString());
      }
      final List<dynamic>? purchases = response.pastPurchases as List<dynamic>?;
      return purchases?.cast<PurchaseDetails>() ?? <PurchaseDetails>[];
    } catch (_) {
      return <PurchaseDetails>[];
    }
  }

  int _purchaseTimestamp(PurchaseDetails details) {
    if (details.transactionDate == null) return 0;
    return int.tryParse(details.transactionDate!) ?? 0;
  }

  Future<void> _ensureBillingReady({required String operation}) async {
    final available = await _inAppPurchase.isAvailable();
    if (available) return;
    await CrashlyticsLogger.recordNonFatal(
      reason: 'BILLING_UNAVAILABLE',
      error: StateError('Store not available'),
      context: {'operation': operation},
    );
    throw StateError('Store not available');
  }
}
