// providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_receipt_repository.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_trip_repository.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_account_repository.dart';
import 'package:receiptnest/data/services/auth/auth_service.dart';
import 'package:receiptnest/data/services/auth/firebase_auth_service.dart'
    as fb_impl;
import 'package:receiptnest/data/services/cloud_ocr_service.dart';
import 'package:receiptnest/data/services/stub_export_service.dart';
import 'package:receiptnest/data/services/stub_insights_service.dart';
import 'package:receiptnest/data/services/ocr/chatgpt_ocr_service.dart';
import 'package:receiptnest/data/services/image_processing/receipt_image_processing_service.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_user_repository.dart';
import 'package:receiptnest/domain/entities/ocr_result.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/services/ocr_service.dart';
import 'package:receiptnest/domain/services/export_service.dart';
import 'package:receiptnest/domain/services/insights_service.dart';
import 'package:receiptnest/domain/services/subscription_service.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/domain/policies/account_policies.dart';
import 'package:receiptnest/domain/repositories/receipt_repository.dart';
import 'package:receiptnest/domain/repositories/account_repository.dart';
import 'package:receiptnest/domain/repositories/trip_repository.dart';
import 'package:receiptnest/domain/repositories/user_repository.dart';
import 'package:receiptnest/domain/usecases/add_receipt.dart';
import 'package:receiptnest/domain/usecases/create_trip.dart';
import 'package:receiptnest/domain/usecases/delete_account.dart';
import 'package:receiptnest/domain/usecases/delete_trip.dart';
import 'package:receiptnest/domain/usecases/get_receipt_by_id.dart';
import 'package:receiptnest/domain/usecases/get_receipts.dart';
import 'package:receiptnest/domain/usecases/get_trip.dart';
import 'package:receiptnest/domain/usecases/get_trips.dart';
import 'package:receiptnest/domain/usecases/update_trip.dart';
import 'package:receiptnest/domain/usecases/watch_trip.dart';
import 'package:receiptnest/domain/usecases/watch_trips.dart';
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

// Stream of the current user (null when logged out)
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

// Convenience: expose current uid (null if signed out)
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

/// Chooses the production OCR service pipeline (Vision + GPT parsing)
final ocrServiceProvider = Provider<OcrService>((ref) {
  return _OcrPipeline(
    vision: ref.read(cloudOcrServiceProvider),
    parser: ref.read(chatGptOcrServiceProvider),
  );
});

/// Pipeline: Vision extracts → ChatGPT parses
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

// Repository (use Firebase by default)
final Provider<ReceiptRepository> receiptRepositoryProviderOverride =
    Provider<ReceiptRepository>((ref) {
  return FirebaseReceiptRepository();
});

final Provider<TripRepository> tripRepositoryProvider =
    Provider<TripRepository>((ref) {
  return FirebaseTripRepository();
});

final Provider<ExportService> exportServiceProvider = Provider<ExportService>((
  ref,
) {
  return const StubExportService();
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

// Use-cases
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

final createTripUseCaseProvider =
    Provider.autoDispose<CreateTripUseCase>((ref) {
  final repository = ref.read(tripRepositoryProvider);
  return CreateTripUseCase(repository);
});

final updateTripUseCaseProvider =
    Provider.autoDispose<UpdateTripUseCase>((ref) {
  final repository = ref.read(tripRepositoryProvider);
  return UpdateTripUseCase(repository);
});

final deleteTripUseCaseProvider =
    Provider.autoDispose<DeleteTripUseCase>((ref) {
  final repository = ref.read(tripRepositoryProvider);
  return DeleteTripUseCase(repository);
});

final getTripUseCaseProvider = Provider.autoDispose<GetTripUseCase>((ref) {
  final repository = ref.read(tripRepositoryProvider);
  return GetTripUseCase(repository);
});

final getTripsUseCaseProvider = Provider.autoDispose<GetTripsUseCase>((ref) {
  final repository = ref.read(tripRepositoryProvider);
  return GetTripsUseCase(repository);
});

final watchTripUseCaseProvider = Provider.autoDispose<WatchTripUseCase>((ref) {
  final repository = ref.read(tripRepositoryProvider);
  return WatchTripUseCase(repository);
});

final watchTripsUseCaseProvider =
    Provider.autoDispose<WatchTripsUseCase>((ref) {
  final repository = ref.read(tripRepositoryProvider);
  return WatchTripsUseCase(repository);
});

final deleteAccountUseCaseProvider =
    Provider.autoDispose<DeleteAccountUseCase>((ref) {
  final repository = ref.read(accountRepositoryProvider);
  return DeleteAccountUseCase(repository);
});

/// ---------------------------------------------------------------------------
/// NEW: Stream-based receipts provider (fixes sync delays completely)
/// ---------------------------------------------------------------------------
final receiptsProvider = StreamProvider.autoDispose<List<Receipt>>((ref) {
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
    return snapshot.docs.map((doc) => doc.data()).toList();
  });
});

/// Single receipt detail provider
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

final premiumTripAccessProvider = Provider<bool>((ref) {
  return ref.watch(accountEligibilityProvider)?.isPremiumEligible ?? false;
});

final tripsStreamProvider = StreamProvider<List<Trip>>((ref) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) {
    return const Stream<List<Trip>>.empty();
  }

  final watchTrips = ref.read(watchTripsUseCaseProvider);
  return watchTrips(uid);
});

final tripsProvider = tripsStreamProvider;

final tripsListProvider = FutureProvider.autoDispose<List<Trip>>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return const <Trip>[];
  }

  final getTrips = ref.read(getTripsUseCaseProvider);
  return getTrips(uid);
});

final tripProvider = FutureProvider.autoDispose.family<Trip?, String>((
  ref,
  tripId,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Future<Trip?>.value(null);
  }

  final getTrip = ref.read(getTripUseCaseProvider);
  return getTrip(uid, tripId);
});

final tripStreamProvider =
    StreamProvider.autoDispose.family<Trip?, String>((ref, tripId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return const Stream<Trip?>.empty();
  }

  final watchTrip = ref.read(watchTripUseCaseProvider);
  return watchTrip(uid, tripId);
});

final tripReceiptsStreamProvider =
    StreamProvider.autoDispose.family<List<Receipt>, String>((ref, tripId) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) {
    return const Stream<List<Receipt>>.empty();
  }

  final repository = ref.read(tripRepositoryProvider);
  return repository.watchReceiptsForTrip(uid, tripId);
});
