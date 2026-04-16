// providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_account_repository.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_collection_repository.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_receipt_repository.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_user_repository.dart';
import 'package:receiptnest/data/services/auth/auth_service.dart';
import 'package:receiptnest/data/services/auth/firebase_auth_service.dart'
    as fb_impl;
import 'package:receiptnest/data/services/cloud_ocr_service.dart';
import 'package:receiptnest/data/services/export/on_device_export_dependencies.dart';
import 'package:receiptnest/data/services/export/on_device_receipt_export_service.dart';
import 'package:receiptnest/data/services/image_processing/receipt_image_processing_service.dart';
import 'package:receiptnest/data/services/ocr/chatgpt_ocr_service.dart';
import 'package:receiptnest/data/services/stub_export_service.dart';
import 'package:receiptnest/data/services/stub_insights_service.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/entities/ocr_result.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/policies/account_policies.dart';
import 'package:receiptnest/domain/repositories/account_repository.dart';
import 'package:receiptnest/domain/repositories/collection_repository.dart';
import 'package:receiptnest/domain/repositories/receipt_repository.dart';
import 'package:receiptnest/domain/repositories/user_repository.dart';
import 'package:receiptnest/domain/services/export/builders/image_export_collector.dart';
import 'package:receiptnest/domain/services/export/export_engine.dart';
import 'package:receiptnest/domain/services/export/export_file_namer.dart';
import 'package:receiptnest/domain/services/export_service.dart';
import 'package:receiptnest/domain/services/insights_service.dart';
import 'package:receiptnest/domain/services/ocr_service.dart';
import 'package:receiptnest/domain/services/subscription_service.dart';
import 'package:receiptnest/domain/usecases/add_receipt.dart';
import 'package:receiptnest/domain/usecases/create_collection.dart';
import 'package:receiptnest/domain/usecases/delete_account.dart';
import 'package:receiptnest/domain/usecases/delete_collection.dart';
import 'package:receiptnest/domain/usecases/get_collection.dart';
import 'package:receiptnest/domain/usecases/get_collections.dart';
import 'package:receiptnest/domain/usecases/get_receipt_by_id.dart';
import 'package:receiptnest/domain/usecases/get_receipts.dart';
import 'package:receiptnest/domain/usecases/update_collection.dart';
import 'package:receiptnest/domain/usecases/watch_collection.dart';
import 'package:receiptnest/domain/usecases/watch_collections.dart';
import 'package:receiptnest/presentation/providers/app_config_provider.dart';
import 'package:receiptnest/presentation/providers/auth_controller.dart';
import 'package:receiptnest/services/connectivity_service.dart';
import 'package:receiptnest/services/receipt_image_source_service.dart';

final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  return fb_impl.FirebaseAuthService();
});

final receiptImageProcessingServiceProvider =
    Provider<ReceiptImageProcessingService>((ref) {
  return ReceiptImageProcessingService();
});

final receiptImageSourceServiceProvider =
    Provider<ReceiptImageSourceService>((ref) {
  return ReceiptImageSourceService();
});

final connectivityServiceProvider =
    Provider<ConnectivityService>((ref) => ConnectivityService());

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthController(authService);
});

final Provider<UserRepository> userRepositoryProvider =
    Provider<UserRepository>((ref) {
  return FirebaseUserRepository();
});

final Provider<SubscriptionService> subscriptionServiceProvider =
    Provider<SubscriptionService>((ref) {
  return StoreSubscriptionService();
});

final Provider<AccountRepository> accountRepositoryProvider =
    Provider<AccountRepository>((ref) {
  return FirebaseAccountRepository();
});

final userProfileProvider = FutureProvider<AppUserProfile?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return null;
  }
  final repository = ref.read(userRepositoryProvider);
  return repository.getCurrentUserProfile();
});

final currentUidProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider).value;
  return auth?.uid;
});

final userIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUidProvider);
});

final cloudOcrServiceProvider = Provider<CloudOcrService>((ref) {
  return CloudOcrService();
});

final chatGptOcrServiceProvider = Provider<ChatGptOcrService>((ref) {
  final openAiKey = dotenv.env['OPENAI_API_KEY'];
  if (openAiKey == null || openAiKey.isEmpty) {
    throw Exception("Missing OPENAI_API_KEY in .env");
  }
  return ChatGptOcrService(openAiApiKey: openAiKey);
});

final ocrServiceProvider = Provider<OcrService>((ref) {
  return _OcrPipeline(
    vision: ref.read(cloudOcrServiceProvider),
    parser: ref.read(chatGptOcrServiceProvider),
  );
});

class _OcrPipeline implements OcrService {
  final CloudOcrService vision;
  final ChatGptOcrService parser;

  _OcrPipeline({required this.vision, required this.parser});

  @override
  Future<OcrResult> parseImage(String imagePathOrUrl) async {
    final visionResult = await vision.parseImage(imagePathOrUrl);
    return parser.parseRawText(visionResult.rawText);
  }

  @override
  Future<OcrResult> parseRawText(String rawText) {
    return parser.parseRawText(rawText);
  }

  @override
  Future<OcrResult> parsePdf(String pdfPath) async {
    throw UnimplementedError(
      "Extract PDF text in UI, then call parseRawText().",
    );
  }
}

final Provider<ReceiptRepository> receiptRepositoryProviderOverride =
    Provider<ReceiptRepository>((ref) {
  return FirebaseReceiptRepository();
});

final Provider<CollectionRepository> collectionRepositoryProvider =
    Provider<CollectionRepository>((ref) {
  return FirebaseCollectionRepository();
});

final Provider<ExportService> exportServiceProvider = Provider<ExportService>((
  ref,
) {
  return const StubExportService();
});

final exportWorkingDirectoryProvider =
    Provider<ExportWorkingDirectoryProvider>((ref) {
  return const SystemExportWorkingDirectoryProvider();
});

final exportReceiptFileResolverProvider =
    Provider<ExportReceiptFileResolver>((ref) {
  return const OnDeviceExportReceiptFileResolver();
});

final exportShareLauncherProvider = Provider<ExportShareLauncher>((ref) {
  return const SharePlusExportShareLauncher();
});

final exportEngineProvider = Provider<ExportEngine>((ref) {
  return OnDeviceExportEngine(
    workingDirectoryProvider: ref.read(exportWorkingDirectoryProvider),
    imageExportCollector: ImageExportCollector(
      fileResolver: ref.read(exportReceiptFileResolverProvider),
      fileNamer: const ExportFileNamer(),
    ),
  );
});

final receiptExportServiceProvider =
    Provider<OnDeviceReceiptExportService>((ref) {
  return OnDeviceReceiptExportService(
    exportEngine: ref.read(exportEngineProvider),
    shareLauncher: ref.read(exportShareLauncherProvider),
  );
});

final Provider<InsightsService> insightsServiceProvider =
    Provider<InsightsService>((ref) {
  return const StubInsightsService();
});

final receiptCountProvider = FutureProvider<int>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return 0;
  }
  final repository = ref.read(receiptRepositoryProviderOverride);
  return repository.getReceiptCount();
});

final AutoDisposeProvider<AddReceiptUseCase> addReceiptUseCaseProviderOverride =
    Provider.autoDispose<AddReceiptUseCase>((ref) {
  final ReceiptRepository repository =
      ref.read(receiptRepositoryProviderOverride);
  final UserRepository userRepository = ref.read(userRepositoryProvider);
  return AddReceiptUseCase(
    repository,
    userRepository,
    () => ref.read(appConfigProvider.future),
  );
});

final AutoDisposeProvider<GetReceiptsUseCase>
    getReceiptsUseCaseProviderOverride =
    Provider.autoDispose<GetReceiptsUseCase>((ref) {
  final ReceiptRepository repository =
      ref.read(receiptRepositoryProviderOverride);
  return GetReceiptsUseCase(repository);
});

final getReceiptByIdUseCaseProvider =
    Provider.autoDispose<GetReceiptByIdUseCase>((ref) {
  final ReceiptRepository repository =
      ref.read(receiptRepositoryProviderOverride);
  return GetReceiptByIdUseCase(repository);
});

final createCollectionUseCaseProvider =
    Provider.autoDispose<CreateCollectionUseCase>((ref) {
  final repository = ref.read(collectionRepositoryProvider);
  return CreateCollectionUseCase(repository);
});

final updateCollectionUseCaseProvider =
    Provider.autoDispose<UpdateCollectionUseCase>((ref) {
  final repository = ref.read(collectionRepositoryProvider);
  return UpdateCollectionUseCase(repository);
});

final deleteCollectionUseCaseProvider =
    Provider.autoDispose<DeleteCollectionUseCase>((ref) {
  final repository = ref.read(collectionRepositoryProvider);
  return DeleteCollectionUseCase(repository);
});

final getCollectionUseCaseProvider =
    Provider.autoDispose<GetCollectionUseCase>((ref) {
  final repository = ref.read(collectionRepositoryProvider);
  return GetCollectionUseCase(repository);
});

final getCollectionsUseCaseProvider =
    Provider.autoDispose<GetCollectionsUseCase>((ref) {
  final repository = ref.read(collectionRepositoryProvider);
  return GetCollectionsUseCase(repository);
});

final watchCollectionUseCaseProvider =
    Provider.autoDispose<WatchCollectionUseCase>((ref) {
  final repository = ref.read(collectionRepositoryProvider);
  return WatchCollectionUseCase(repository);
});

final watchCollectionsUseCaseProvider =
    Provider.autoDispose<WatchCollectionsUseCase>((ref) {
  final repository = ref.read(collectionRepositoryProvider);
  return WatchCollectionsUseCase(repository);
});

final deleteAccountUseCaseProvider =
    Provider.autoDispose<DeleteAccountUseCase>((ref) {
  final repository = ref.read(accountRepositoryProvider);
  return DeleteAccountUseCase(repository);
});

final receiptCollectionOverridesProvider =
    StateProvider<Map<String, String?>>((ref) {
  return <String, String?>{};
});

final receiptsProvider = StreamProvider.autoDispose<List<Receipt>>((ref) {
  final collectionOverrides = ref.watch(receiptCollectionOverridesProvider);
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return const Stream<List<Receipt>>.empty();
  }

  final collection = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('receipts')
      .withConverter<Receipt>(
        fromFirestore: (snapshot, _) => Receipt.fromFirestore(snapshot),
        toFirestore: (receipt, _) => receipt.toMap(),
      )
      .orderBy('createdAt', descending: true);

  return collection.snapshots().map((snapshot) {
    final receipts = snapshot.docs.map((doc) => doc.data()).toList();
    if (collectionOverrides.isEmpty) {
      return receipts;
    }

    final nextOverrides = Map<String, String?>.from(collectionOverrides);
    final updatedReceipts = <Receipt>[
      for (final receipt in receipts)
        if (nextOverrides.containsKey(receipt.id))
          if (receipt.collectionId == nextOverrides[receipt.id])
            () {
              nextOverrides.remove(receipt.id);
              return receipt;
            }()
          else
            receipt.copyWith(collectionId: nextOverrides[receipt.id])
        else
          receipt,
    ];

    if (nextOverrides.length != collectionOverrides.length) {
      Future<void>.microtask(() {
        ref.read(receiptCollectionOverridesProvider.notifier).state =
            nextOverrides;
      });
    }

    return updatedReceipts;
  });
});

final receiptDetailProvider =
    FutureProvider.autoDispose.family<Receipt?, String>((ref, receiptId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Future<Receipt?>.value(null);
  }
  final getReceipt = ref.read(getReceiptByIdUseCaseProvider);
  return getReceipt(receiptId);
});

final accountEligibilityProvider = Provider<AccountEligibility?>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  if (profile == null) {
    return null;
  }

  return AccountPolicies.evaluate(profile, DateTime.now().toUtc());
});

final premiumCollectionAccessProvider = Provider<bool>((ref) {
  return ref.watch(accountEligibilityProvider)?.isPremiumEligible ?? false;
});

final collectionsStreamProvider = StreamProvider<List<Collection>>((ref) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) {
    return const Stream<List<Collection>>.empty();
  }

  final watchCollections = ref.read(watchCollectionsUseCaseProvider);
  return watchCollections(uid);
});

final collectionsProvider = FutureProvider<List<Collection>>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return const <Collection>[];
  }

  final getCollections = ref.read(getCollectionsUseCaseProvider);
  return getCollections(uid);
});

final collectionsListProvider = collectionsProvider;

final collectionProvider =
    FutureProvider.autoDispose.family<Collection?, String>((
  ref,
  collectionId,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Future<Collection?>.value(null);
  }

  final getCollection = ref.read(getCollectionUseCaseProvider);
  return getCollection(uid, collectionId);
});

final collectionStreamProvider =
    StreamProvider.autoDispose.family<Collection?, String>((
  ref,
  collectionId,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return const Stream<Collection?>.empty();
  }

  final watchCollection = ref.read(watchCollectionUseCaseProvider);
  return watchCollection(uid, collectionId);
});

final collectionReceiptsStreamProvider =
    StreamProvider.autoDispose.family<List<Receipt>, String>((
  ref,
  collectionId,
) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) {
    return const Stream<List<Receipt>>.empty();
  }

  final repository = ref.read(collectionRepositoryProvider);
  return repository.watchReceiptsForCollection(uid, collectionId);
});
