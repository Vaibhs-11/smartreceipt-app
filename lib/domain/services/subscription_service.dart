import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';

abstract class SubscriptionService {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<void> restorePurchases();
  Future<List<ProductDetails>> fetchProducts();
  Future<void> purchase(ProductDetails product, {required String accountToken});
  Future<void> completePurchase(PurchaseDetails purchase);
}

class PurchaseCancelledException implements Exception {}

class PurchasePendingException implements Exception {}

class SubscriptionProductIds {
  static String? _value(String name) {
    final value = dotenv.env[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? monthlyId() => Platform.isIOS
      ? _value('IOS_SUBSCRIPTION_MONTHLY_ID')
      : Platform.isAndroid
          ? _value('ANDROID_SUBSCRIPTION_MONTHLY_ID')
          : null;
  static String? yearlyId() => Platform.isIOS
      ? _value('IOS_SUBSCRIPTION_YEARLY_ID')
      : Platform.isAndroid
          ? _value('ANDROID_SUBSCRIPTION_YEARLY_ID')
          : null;
  static Set<String> allIds() {
    final monthly = monthlyId();
    final yearly = yearlyId();
    if (monthly == null || yearly == null) {
      throw StateError('Missing subscription product IDs');
    }
    return {monthly, yearly};
  }

  static SubscriptionTier? tierForProduct(String productId) {
    if (productId == monthlyId()) return SubscriptionTier.monthly;
    if (productId == yearlyId()) return SubscriptionTier.yearly;
    return null;
  }

  static SubscriptionSource? platformSource() => Platform.isIOS
      ? SubscriptionSource.apple
      : Platform.isAndroid
          ? SubscriptionSource.google
          : null;
}

class StoreSubscriptionService implements SubscriptionService {
  StoreSubscriptionService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;
  final InAppPurchase _inAppPurchase;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;
  Future<void> _ensureAvailable() async {
    if (!await _inAppPurchase.isAvailable()) {
      throw StateError('Store unavailable');
    }
  }

  @override
  Future<List<ProductDetails>> fetchProducts() async {
    await _ensureAvailable();
    final result = await _inAppPurchase
        .queryProductDetails(SubscriptionProductIds.allIds());
    if (result.error != null) {
      throw StateError('Unable to load subscription prices');
    }
    return result.productDetails;
  }

  @override
  Future<void> purchase(ProductDetails product,
      {required String accountToken}) async {
    await _ensureAvailable();
    if (Platform.isIOS) {
      // 0.4.7's generic adapter discards the pending/cancelled return value.
      final result = await SK2Product.purchase(product.id,
          options: SK2ProductPurchaseOptions(appAccountToken: accountToken));
      if (result == SK2ProductPurchaseResult.userCancelled) {
        throw PurchaseCancelledException();
      }
      if (result == SK2ProductPurchaseResult.pending) {
        throw PurchasePendingException();
      }
      if (result != SK2ProductPurchaseResult.success) {
        throw StateError('Store could not verify the purchase');
      }
      return;
    }
    final started = await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(
          productDetails: product, applicationUserName: accountToken),
    );
    if (!started) throw StateError('Purchase could not be started');
  }

  @override
  Future<void> restorePurchases() async {
    await _ensureAvailable();
    await _inAppPurchase.restorePurchases();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    // 0.4.7 labels signed SK2 purchases restored, even on initial purchase,
    // making pendingCompletePurchase false. Finishing is idempotent in SK2.
    if (purchase is SK2PurchaseDetails || purchase.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchase);
    }
  }
}
