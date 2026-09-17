import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class VerifiedPurchaseResult {
  const VerifiedPurchaseResult({required this.active});
  final bool active;
}

abstract class SubscriptionBackend {
  Future<String> accountToken(String uid);
  Future<VerifiedPurchaseResult> verify(PurchaseDetails purchase, String uid,
      {required bool restore});
}

class FirebaseSubscriptionBackend implements SubscriptionBackend {
  FirebaseSubscriptionBackend({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _functions;

  @override
  Future<String> accountToken(String uid) async {
    final result = await _functions
        .httpsCallable('getSubscriptionAccountToken')
        .call<Map<String, dynamic>>();
    final token = result.data['token'];
    if (token is! String || token.isEmpty) {
      throw StateError('Account token unavailable');
    }
    return token;
  }

  @override
  Future<VerifiedPurchaseResult> verify(PurchaseDetails purchase, String uid,
      {required bool restore}) async {
    final source = purchase.verificationData.source;
    final result = await _functions
        .httpsCallable('syncSubscriptionEntitlement')
        .call<Map<String, dynamic>>({
      'expectedUid': uid,
      'source': source == 'app_store'
          ? 'apple'
          : source == 'google_play'
              ? 'google'
              : source,
      'productId': purchase.productID,
      'purchaseId': purchase.purchaseID,
      'verificationData': purchase.verificationData.serverVerificationData,
      'restore': restore,
    });
    final data = result.data;
    if (data['accepted'] != true) {
      throw StateError('Purchase verification was not accepted');
    }
    return VerifiedPurchaseResult(
        active: data['status'] == 'active' &&
            ['monthly', 'yearly'].contains(data['tier']));
  }
}
