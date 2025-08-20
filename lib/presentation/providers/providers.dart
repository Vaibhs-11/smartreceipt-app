import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/core/config/app_config.dart';
import 'package:smartreceipt/data/repositories/local/local_receipt_repository.dart';
import 'package:smartreceipt/data/repositories/firebase/firebase_receipt_repository.dart';
import 'package:smartreceipt/data/services/ai/ai_tagging_service.dart';
import 'package:smartreceipt/data/services/ai/openai_tagger_stub.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';
import 'package:smartreceipt/data/services/auth/firebase_auth_service.dart';
import 'package:smartreceipt/core/config/app_config.dart';
import 'package:smartreceipt/data/services/notifications/notifications_service.dart';
import 'package:smartreceipt/data/services/ocr/google_vision_ocr_stub.dart';
import 'package:smartreceipt/data/services/ocr/ocr_service.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';
import 'package:smartreceipt/domain/usecases/add_receipt.dart';
import 'package:smartreceipt/domain/usecases/get_receipts.dart';

// Services (stubbed by default)
final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  final AppConfig config = ref.read(appConfigProvider);
  //if (config.useStubs) return AuthServiceStub();
  return FirebaseAuthService();
});

final Provider<OcrService> ocrServiceProvider = Provider<OcrService>((ref) {
  return GoogleVisionOcrStub();
});

final Provider<AiTaggingService> aiTaggingServiceProvider =
    Provider<AiTaggingService>((ref) => OpenAiTaggerStub());

final Provider<NotificationsService> notificationsServiceProvider =
    Provider<NotificationsService>((ref) => NotificationsServiceStub());

// Repository (local memory stub for MVP offline)
final Provider<ReceiptRepository> receiptRepositoryProviderOverride =
    Provider<ReceiptRepository>((ref) {
  final AppConfig config = ref.read(appConfigProvider);
  if (config.useStubs) return LocalReceiptRepository();
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

// Receipt list provider
final FutureProvider<List<dynamic>> receiptsProvider =
    FutureProvider<List<dynamic>>((ref) async {
  final GetReceiptsUseCase getReceipts = ref.read(getReceiptsUseCaseProviderOverride);
  return getReceipts();
});


