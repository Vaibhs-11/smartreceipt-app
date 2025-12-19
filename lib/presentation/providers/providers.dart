// providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/data/repositories/firebase/firebase_receipt_repository.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';
import 'package:smartreceipt/data/services/auth/firebase_auth_service.dart'
    as fb_impl;
import 'package:smartreceipt/data/services/cloud_ocr_service.dart';
import 'package:smartreceipt/data/services/ocr/chatgpt_ocr_service.dart';
import 'package:smartreceipt/data/services/image_processing/receipt_image_processing_service.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';
import 'package:smartreceipt/domain/usecases/add_receipt.dart';
import 'package:smartreceipt/domain/usecases/get_receipt_by_id.dart';
import 'package:smartreceipt/domain/usecases/get_receipts.dart';
import 'package:smartreceipt/presentation/providers/auth_controller.dart';
import 'package:smartreceipt/services/receipt_image_source_service.dart';

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

/// Chooses the production OCR service pipeline (Vision + GPT parsing)
final ocrServiceProvider = Provider<OcrService>((ref) {
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
  final getReceipt = ref.read(getReceiptByIdUseCaseProvider);
  return getReceipt(receiptId);
});
