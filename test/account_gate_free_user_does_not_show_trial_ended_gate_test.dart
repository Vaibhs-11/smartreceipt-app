import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/domain/repositories/receipt_repository.dart';
import 'package:receiptnest/domain/repositories/user_repository.dart';
import 'package:receiptnest/domain/services/subscription_service.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/trial_ended_gate_screen.dart';
import 'package:receiptnest/presentation/widgets/account_gate.dart';
import 'package:receiptnest/services/connectivity_service.dart';

void main() {
  testWidgets('Free user without trial or downgrade does not show trial ended gate', (
    WidgetTester tester,
  ) async {
    final freeProfile = AppUserProfile(
      uid: 'uid-free',
      email: 'free@example.com',
      isAnonymous: false,
      createdAt: DateTime.now().toUtc(),
      accountStatus: AccountStatus.free,
      subscriptionTier: SubscriptionTier.free,
      subscriptionStatus: SubscriptionStatus.none,
      trialDowngradeRequired: false,
      trialEndsAt: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('uid-free'),
          userRepositoryProvider.overrideWithValue(
            _FakeUserRepository(profile: freeProfile),
          ),
          subscriptionServiceProvider.overrideWithValue(_FakeSubscriptionService()),
          receiptRepositoryProviderOverride.overrideWithValue(
            _FakeReceiptRepository(),
          ),
          connectivityServiceProvider.overrideWithValue(
            _AlwaysConnectedConnectivityService(),
          ),
          
        ],
        child: MaterialApp(
          home: const AccountGate(
            child: Scaffold(body: Center(child: Text('Home'))),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(TrialEndedGateScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository({required this.profile});

  final AppUserProfile profile;

  @override
  Future<void> applySubscriptionEntitlement(
    SubscriptionEntitlement entitlement, {
    AppUserProfile? currentProfile,
  }) async {}

  @override
  Future<void> clearDowngradeRequired() async {}

  @override
  Future<AppUserProfile?> getCurrentUserProfile() async => profile;

  @override
  Future<void> markDowngradeRequired() async {}

  @override
  Future<void> startTrial() async {}
}

class _FakeReceiptRepository implements ReceiptRepository {
  @override
  Future<void> addReceipt(Receipt receipt) async {}

  @override
  Future<void> deleteReceipt(String id) async {}

  @override
  Future<List<Receipt>> getReceipts() async => const [];

  @override
  Future<Receipt?> getReceiptById(String id) async => null;

  @override
  Future<int> getReceiptCount() async => 0;

  @override
  Future<void> assignReceiptsToCollection(
    List<String> receiptIds,
    String collectionId,
  ) async {}

  @override
  Future<void> removeReceiptFromCollection(String receiptId) async {}

  @override
  Future<void> removeReceiptsFromCollection(List<String> receiptIds) async {}

  @override
  Future<void> moveReceiptToCollection(
    String receiptId,
    String newCollectionId,
  ) async {}

  @override
  Future<void> updateReceipt(Receipt receipt) async {}
}

class _FakeSubscriptionService implements SubscriptionService {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream async* {
    yield const <PurchaseDetails>[];
  }

  @override
  Future<List<ProductDetails>> fetchProducts() async => const <ProductDetails>[];

  @override
  Future<SubscriptionEntitlement> getCurrentEntitlement() async =>
      const SubscriptionEntitlement(
        tier: SubscriptionTier.free,
        status: SubscriptionStatus.none,
      );

  @override
  Future<void> purchase(ProductDetails product) async {}

  @override
  Future<void> restorePurchases() async {}
}

class _AlwaysConnectedConnectivityService implements ConnectivityService {
  @override
  Future<bool> hasInternetConnection() async => true;
}
