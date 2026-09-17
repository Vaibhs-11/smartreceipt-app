import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:receiptnest/data/services/subscription_backend.dart';
import 'package:receiptnest/domain/services/subscription_service.dart';
import 'package:receiptnest/presentation/providers/subscription_controller.dart';

class TestStore implements SubscriptionService {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  List<PurchaseDetails> restored = [];
  final List<String> operations = [];
  Object? launchError;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<List<ProductDetails>> fetchProducts() async => [];
  @override
  Future<void> purchase(ProductDetails product,
      {required String accountToken}) async {
    operations.add('launch:$accountToken');
    if (launchError != null) throw launchError!;
  }

  @override
  Future<void> restorePurchases() async {
    events.add(restored);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    operations.add('finish');
  }
}

class TestBackend implements SubscriptionBackend {
  TestBackend(this.operations);
  final List<String> operations;
  bool fail = false;
  bool active = true;
  Completer<void>? wait;
  @override
  Future<String> accountToken(String uid) async => 'token-$uid';
  @override
  Future<VerifiedPurchaseResult> verify(PurchaseDetails purchase, String uid,
      {required bool restore}) async {
    operations.add('verify:$uid');
    if (wait != null) await wait!.future;
    if (fail) throw StateError('Unavailable');
    operations.add('persist');
    return VerifiedPurchaseResult(active: active);
  }
}

PurchaseDetails purchase(
        {PurchaseStatus status = PurchaseStatus.purchased,
        String product = 'monthly',
        String id = 'tx1'}) =>
    PurchaseDetails(
      productID: product,
      purchaseID: id,
      status: status,
      verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: 'signed-evidence',
          source: 'app_store'),
      transactionDate: '123',
    );

void main() {
  late TestStore store;
  late TestBackend backend;
  late SubscriptionController controller;
  String? uid;
  setUp(() {
    uid = 'u1';
    store = TestStore();
    backend = TestBackend(store.operations);
    controller = SubscriptionController(
        service: store,
        backend: backend,
        currentUid: () => uid,
        onVerified: () => store.operations.add('refresh'),
        isSubscriptionProduct: (id) => ['monthly', 'yearly'].contains(id));
  });
  tearDown(() async {
    controller.dispose();
    await store.events.close();
  });
  Future<void> deliver(PurchaseDetails item) async {
    store.events.add([item]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test('payment evidence is persisted before refresh and finish', () async {
    await deliver(purchase());
    expect(store.operations, ['verify:u1', 'persist', 'refresh', 'finish']);
    expect(controller.phase, SubscriptionPhase.active);
  });
  test('signed SK2 restored event is finished despite pending flag being false',
      () async {
    await deliver(purchase(status: PurchaseStatus.restored));
    expect(store.operations.last, 'finish');
  });
  test('failed verification never finishes or refreshes; retry restores',
      () async {
    backend.fail = true;
    await deliver(purchase());
    expect(store.operations, ['verify:u1']);
    expect(controller.phase, SubscriptionPhase.error);
    backend.fail = false;
    store.restored = [purchase(status: PurchaseStatus.restored)];
    expect(await controller.restore(), 1);
    expect(store.operations.last, 'finish');
  });
  test('duplicate callbacks do not finish or persist twice', () async {
    await deliver(purchase());
    await deliver(purchase());
    expect(store.operations.where((x) => x == 'finish').length, 1);
  });
  test('empty restore does not change free or trial profile', () async {
    expect(await controller.restore(), 0);
    expect(store.operations, isEmpty);
    expect(controller.phase, SubscriptionPhase.idle);
  });
  test('restore waits for backend persistence', () async {
    backend.wait = Completer<void>();
    store.restored = [purchase(status: PurchaseStatus.restored)];
    bool done = false;
    final result = controller.restore().then((value) {
      done = true;
      return value;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(done, false);
    expect(store.operations, ['verify:u1']);
    backend.wait!.complete();
    expect(await result, 1);
  });
  test('failed restore reports failure instead of success', () async {
    backend.fail = true;
    store.restored = [purchase(status: PurchaseStatus.restored)];
    await expectLater(controller.restore(), throwsStateError);
    expect(store.operations, ['verify:u1']);
  });
  for (final status in [
    PurchaseStatus.pending,
    PurchaseStatus.canceled,
    PurchaseStatus.error
  ]) {
    test('$status never grants or finishes a purchase', () async {
      await deliver(purchase(status: status));
      expect(store.operations, isEmpty);
    });
  }
  test('unrelated products are ignored', () async {
    await deliver(purchase(product: 'unknown'));
    expect(store.operations, isEmpty);
  });
  test(
      'account change during verification cannot refresh or finish for new user',
      () async {
    backend.wait = Completer<void>();
    await deliver(purchase());
    uid = 'u2';
    controller.accountChanged();
    backend.wait!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(store.operations, ['verify:u1', 'persist']);
    expect(controller.phase, SubscriptionPhase.idle);
  });
  test('signed out users do not submit purchase evidence', () async {
    uid = null;
    await deliver(purchase());
    expect(store.operations, isEmpty);
  });
}
