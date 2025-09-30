import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartreceipt/core/config/app_config.dart';
import 'package:smartreceipt/data/services/cloud_ocr_service.dart';
import 'package:smartreceipt/data/repositories/firebase/firebase_receipt_repository.dart';
import 'package:smartreceipt/data/services/ai/ai_tagging_service.dart';
import 'package:smartreceipt/data/services/ai/openai_tagger_stub.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';
import 'package:smartreceipt/data/services/auth/firebase_auth_service.dart'
    as fb_impl;
import 'package:smartreceipt/presentation/providers/auth_controller.dart';
import 'package:smartreceipt/data/services/notifications/notifications_service.dart';
import 'package:smartreceipt/data/services/ocr/google_vision_ocr_stub.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/data/services/ocr/chatgpt_ocr_service.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';
import 'package:smartreceipt/domain/usecases/add_receipt.dart';
import 'package:smartreceipt/domain/usecases/get_receipt_by_id.dart';
import 'package:smartreceipt/domain/usecases/get_receipts.dart';

// Services (stubbed by default)
final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  final AppConfig config = ref.read(appConfigProvider);
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

/// Chooses which OCR service pipeline to use
final ocrServiceProvider = Provider<OcrService>((ref) {
  const useStub = bool.fromEnvironment('USE_OCR_STUB', defaultValue: false);

  if (useStub) {
    return GoogleVisionOcrStub();
  }

  final openAiKey = dotenv.env['OPENAI_API_KEY'];

  if (openAiKey == null || openAiKey.isEmpty) {
    throw Exception("Missing OPENAI_API_KEY in .env");
  }

  return _OcrPipeline(
    vision: CloudOcrService(),
    parser: ChatGptOcrService(openAiApiKey: openAiKey),
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

final Provider<AiTaggingService> aiTaggingServiceProvider =
    Provider<AiTaggingService>((ref) => OpenAiTaggerStub());

final Provider<NotificationsService> notificationsServiceProvider =
    Provider<NotificationsService>((ref) => NotificationsServiceStub());

// Repository (use Firebase by default)
final Provider<ReceiptRepository> receiptRepositoryProviderOverride =
    Provider<ReceiptRepository>((ref) {
  return FirebaseReceiptRepository();
});

// Use-cases
final AutoDisposeProvider<AddReceiptUseCase> addReceiptUseCaseProviderOverride =
    Provider.autoDispose<AddReceiptUseCase>((ref) {
  final ReceiptRepository repository =
      ref.read(receiptRepositoryProviderOverride);
  return AddReceiptUseCase(repository);
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

/// ReceiptsNotifier for Riverpod 1.x
class ReceiptsNotifier extends StateNotifier<AsyncValue<List<Receipt>>> {
  ReceiptsNotifier(this._read) : super(const AsyncValue.loading()) {
    _loadReceipts();
  }

  final Reader _read;

  Future<void> _loadReceipts() async {
    try {
      final getReceipts = _read(getReceiptsUseCaseProviderOverride);
      final receipts = await getReceipts();
      state = AsyncValue.data(receipts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteReceipt(String id) async {
    try {
      final repo = _read(receiptRepositoryProviderOverride);
      await repo.deleteReceipt(id);

      // Optimistically update state
      state = AsyncValue.data(
        state.value?.where((r) => r.id != id).toList() ?? [],
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refreshReceipts() async {
    state = const AsyncValue.loading();
    await _loadReceipts();
  }
}

/// Receipt list provider (Riverpod 1.x style)
final receiptsProvider = StateNotifierProvider<ReceiptsNotifier,
    AsyncValue<List<Receipt>>>((ref) {
  return ReceiptsNotifier(ref.read);
});

/// Single receipt detail provider
final receiptDetailProvider =
    FutureProvider.autoDispose.family<Receipt?, String>((ref, receiptId) {
  final getReceipt = ref.read(getReceiptByIdUseCaseProvider);
  return getReceipt(receiptId);
});
