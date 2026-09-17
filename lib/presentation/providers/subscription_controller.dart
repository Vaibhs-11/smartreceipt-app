import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:receiptnest/data/services/subscription_backend.dart';
import 'package:receiptnest/domain/services/subscription_service.dart';

enum SubscriptionPhase { idle, purchasing, pending, verifying, active, error }

class SubscriptionController extends ChangeNotifier {
  SubscriptionController(
      {required this.service,
      required this.backend,
      required this.currentUid,
      required this.onVerified,
      required this.isSubscriptionProduct}) {
    _listener = service.purchaseStream.listen(_receive, onError: (Object _) {
      _set(SubscriptionPhase.error,
          'Unable to check purchases. Try Restore purchases.');
    });
  }
  final SubscriptionService service;
  final SubscriptionBackend backend;
  final String? Function() currentUid;
  final void Function() onVerified;
  final bool Function(String) isSubscriptionProduct;
  late final StreamSubscription<List<PurchaseDetails>> _listener;
  Future<void> _queue = Future<void>.value();
  final Map<String, PurchaseDetails> _retry = {};
  final Set<String> _completed = {};
  final Map<String, int> _attempts = {};
  Timer? _retryTimer;
  bool _disposed = false;
  bool _restoring = false;
  String? _operationUid;
  int _verifiedRestores = 0;
  bool _restoreFailed = false;
  SubscriptionPhase phase = SubscriptionPhase.idle;
  String? message;
  bool get busy => [
        SubscriptionPhase.purchasing,
        SubscriptionPhase.pending,
        SubscriptionPhase.verifying
      ].contains(phase);
  bool get hasUnconfirmedPurchase => _retry.isNotEmpty;

  void _set(SubscriptionPhase next, [String? text]) {
    if (_disposed) return;
    phase = next;
    message = text;
    notifyListeners();
  }

  Future<void> purchase(ProductDetails product) async {
    if (busy || _restoring || hasUnconfirmedPurchase) {
      throw StateError('A purchase is already in progress');
    }
    final uid = currentUid();
    if (uid == null) throw StateError('Sign in before subscribing');
    _operationUid = uid;
    _set(SubscriptionPhase.purchasing);
    try {
      final token = await backend.accountToken(uid);
      if (currentUid() != uid) throw StateError('Account changed');
      await service.purchase(product, accountToken: token);
    } on PurchaseCancelledException {
      _set(SubscriptionPhase.idle,
          'Purchase cancelled. Your current plan is unchanged.');
    } on PurchasePendingException {
      _set(SubscriptionPhase.pending, 'Waiting for payment approval.');
    } catch (_) {
      _set(SubscriptionPhase.error,
          'Unable to start purchase. Please try again.');
      rethrow;
    }
  }

  Future<int> restore() async {
    if (_restoring || busy) {
      throw StateError('A purchase is already in progress');
    }
    final uid = currentUid();
    if (uid == null) throw StateError('Sign in before restoring');
    _operationUid = uid;
    _restoring = true;
    _verifiedRestores = 0;
    _restoreFailed = false;
    _set(SubscriptionPhase.verifying);
    try {
      await service.restorePurchases().timeout(const Duration(seconds: 45));
      // Both store adapters emit events before their restore future completes.
      await Future<void>.delayed(Duration.zero);
      await _queue.timeout(const Duration(seconds: 60));
      if (currentUid() != uid || _restoreFailed) {
        throw StateError('Restore could not be verified. Please try again.');
      }
      _set(_verifiedRestores > 0
          ? SubscriptionPhase.active
          : SubscriptionPhase.idle);
      return _verifiedRestores;
    } catch (_) {
      _set(SubscriptionPhase.error,
          'Restore could not be verified. Please try again.');
      rethrow;
    } finally {
      _restoring = false;
    }
  }

  void _receive(List<PurchaseDetails> purchases) {
    final uid = _operationUid ?? currentUid();
    final restoring = _restoring;
    for (final purchase in purchases) {
      if (!isSubscriptionProduct(purchase.productID)) continue;
      _queue = _queue.then((_) => _process(purchase, uid, restoring));
    }
  }

  Future<void> _process(
      PurchaseDetails purchase, String? uid, bool restoring) async {
    if (_disposed) return;
    if (uid == null || currentUid() != uid) return;
    if (purchase.status == PurchaseStatus.pending) {
      _set(SubscriptionPhase.pending, 'Waiting for payment approval.');
      return;
    }
    if (purchase.status == PurchaseStatus.canceled ||
        purchase.status == PurchaseStatus.error) {
      _restoreFailed = restoring;
      _set(
          SubscriptionPhase.error,
          purchase.status == PurchaseStatus.canceled
              ? 'Purchase cancelled. Your current plan is unchanged.'
              : 'Purchase was not completed. Please try again.');
      return;
    }
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return;
    }
    final key = '$uid:${purchase.productID}:${purchase.purchaseID}';
    if (_completed.contains(key) && !restoring) return;
    _set(SubscriptionPhase.verifying, 'Confirming your subscription…');
    try {
      final result = await backend.verify(purchase, uid,
          restore: restoring || purchase.status == PurchaseStatus.restored);
      if (currentUid() != uid || _disposed) return;
      onVerified();
      // Store proof has been accepted and the entitlement persisted first.
      await service.completePurchase(purchase);
      _completed.add(key);
      _retry.remove(key);
      _attempts.remove(key);
      if (restoring && result.active) _verifiedRestores++;
      _set(
          result.active ? SubscriptionPhase.active : SubscriptionPhase.idle,
          result.active
              ? 'Premium is active.'
              : 'No active subscription found.');
    } catch (_) {
      if (currentUid() != uid || _disposed) return;
      _restoreFailed = restoring;
      _retry[key] = purchase;
      final attempts = (_attempts[key] ?? 0) + 1;
      _attempts[key] = attempts;
      _set(SubscriptionPhase.error,
          'Your purchase has not been confirmed yet. Use Restore purchases to retry; do not buy again.');
      _retryTimer?.cancel();
      if (attempts >= 3) return; // Explicit restore remains available.
      _retryTimer = Timer(const Duration(seconds: 30), () {
        if (!_disposed && currentUid() == uid && !_restoring) {
          for (final item in List<PurchaseDetails>.of(_retry.values)) {
            _queue = _queue.then((_) => _process(item, uid, true));
          }
        }
      });
    }
  }

  void accountChanged() {
    if (_operationUid == currentUid()) return;
    _operationUid = currentUid();
    _retryTimer?.cancel();
    _retry.clear();
    _completed.clear();
    _attempts.clear();
    _set(SubscriptionPhase.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _listener.cancel();
    super.dispose();
  }
}
