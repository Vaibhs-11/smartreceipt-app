import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartreceipt/core/config/app_config.dart';
import 'package:smartreceipt/data/services/cloud_ocr_service.dart';
import 'package:smartreceipt/data/repositories/firebase/firebase_receipt_repository.dart';
import 'package:smartreceipt/data/services/ai/ai_tagging_service.dart';
import 'package:smartreceipt/data/services/ai/openai_tagger_stub.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';
import 'package:smartreceipt/data/services/auth/firebase_auth_service.dart' as fb_impl;
import 'package:smartreceipt/presentation/providers/auth_controller.dart';
import 'package:smartreceipt/data/services/notifications/notifications_service.dart';
import 'package:smartreceipt/data/services/ocr/google_vision_ocr_stub.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';
import 'package:smartreceipt/data/services/ocr/chatgpt_ocr_service.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';
import 'package:smartreceipt/domain/usecases/add_receipt.dart';
import 'package:smartreceipt/domain/usecases/get_receipt_by_id.dart';
import 'package:smartreceipt/domain/usecases/get_receipts.dart';

// Services (stubbed by default)
final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  final AppConfig config = ref.read(appConfigProvider);
  //if (config.useStubs) return AuthServiceStub();
  return fb_impl.FirebaseAuthService();
});

// Stream of the current user (null when logged out)
final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthController(authService);
});

// Convenience: expose current uid (null if signed out)
final currentUidProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider).value;
  return auth?.uid;
});

final ocrServiceProvider = Provider<OcrService>((ref) {
  const useStub = bool.fromEnvironment('USE_OCR_STUB', defaultValue: false);

  if (useStub) {
    return GoogleVisionOcrStub();
  } else {
    final openAiKey = dotenv.env['OPENAI_API_KEY'];
    final visionKey = dotenv.env['GOOGLE_VISION_API_KEY'];

    if (openAiKey == null || openAiKey.isEmpty) {
      throw Exception("Missing OPENAI_API_KEY in .env");
    }
    if (visionKey == null || visionKey.isEmpty) {
      throw Exception("Missing GOOGLE_VISION_API_KEY in .env");
    }

    return ChatGptOcrService(openAiKey, visionKey);
  }
});


final Provider<AiTaggingService> aiTaggingServiceProvider =
    Provider<AiTaggingService>((ref) => OpenAiTaggerStub());

final Provider<NotificationsService> notificationsServiceProvider =
    Provider<NotificationsService>((ref) => NotificationsServiceStub());

// Repository (local memory stub for MVP offline)
final Provider<ReceiptRepository> receiptRepositoryProviderOverride =
    Provider<ReceiptRepository>((ref) {
  // The AppConfig logic is great for switching environments, but to ensure
  // we are connecting to Firestore, we will directly return the
  // FirebaseReceiptRepository for now.
  // final AppConfig config = ref.read(appConfigProvider);
  // if (config.useStubs) return LocalReceiptRepository();
  return FirebaseReceiptRepository();
});

// Use-cases
final AutoDisposeProvider<AddReceiptUseCase> addReceiptUseCaseProviderOverride =
    Provider.autoDispose<AddReceiptUseCase>((ref) {
  final ReceiptRepository repository = ref.read(receiptRepositoryProviderOverride);
  return AddReceiptUseCase(repository);
});

final AutoDisposeProvider<GetReceiptsUseCase> getReceiptsUseCaseProviderOverride =
    Provider.autoDispose<GetReceiptsUseCase>((ref) {
  final ReceiptRepository repository = ref.read(receiptRepositoryProviderOverride);
  return GetReceiptsUseCase(repository);
});

final getReceiptByIdUseCaseProvider =
    Provider.autoDispose<GetReceiptByIdUseCase>((ref) {
  final ReceiptRepository repository =
      ref.read(receiptRepositoryProviderOverride);
  return GetReceiptByIdUseCase(repository);
});

// Receipt list provider
final receiptsProvider = FutureProvider<List<Receipt>>((ref) async {
  final getReceipts = ref.read(getReceiptsUseCaseProviderOverride);
  return getReceipts();
});

// Single receipt detail provider
final receiptDetailProvider =
    FutureProvider.autoDispose.family<Receipt?, String>((ref, receiptId) {
  final getReceipt = ref.read(getReceiptByIdUseCaseProvider);
  return getReceipt(receiptId);
});
