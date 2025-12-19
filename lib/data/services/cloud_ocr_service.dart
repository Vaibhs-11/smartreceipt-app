import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

/// CloudOcrService:
/// - Calls a Firebase Cloud Function (httpsCallable 'visionOcr')
///   which must be implemented server-side to use service account credentials.
class CloudOcrService implements OcrService {
  final FirebaseFunctions _functions;

  // 🔑 Define your bucket name here
  static const String _bucket = "smartreceipt-8faff.firebasestorage.app";

  CloudOcrService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<OcrResult> parseImage(String imagePathOrUrl) async {
    final rawText = await _callVisionViaCloudFunction(imagePathOrUrl);

    return OcrResult(
      isReceipt: true,
      storeName: "",
      date: DateTime.now(),
      total: 0.0,
      rawText: rawText,
      items: [],
    );
  }

  @override
  Future<OcrResult> parseRawText(String rawText) async {
    throw UnimplementedError("Use ChatGptOcrService for raw text parsing");
  }

  @override
  Future<OcrResult> parsePdf(String gcsPath) async {
    final callable = _functions.httpsCallable('visionOcr');
    final result = await callable.call({"path": gcsPath});

    final data = Map<String, dynamic>.from(result.data as Map);
    final rawText = data['text'] ?? "";

    return OcrResult(
      isReceipt: true,
      storeName: "",
      date: DateTime.now(),
      total: 0.0,
      rawText: rawText,
      items: [],
    );
  }

  // ----------------- Helpers -----------------

  Future<String> _callVisionViaCloudFunction(String imagePathOrUrl) async {
    final callable = _functions.httpsCallable('visionOcr');

    if (imagePathOrUrl.startsWith('http')) {
      // Case 1: remote URL
      final result = await callable.call({'imageUrl': imagePathOrUrl});
      return _extractTextFromCallableResult(result);

    } else if (imagePathOrUrl.startsWith('receipts/')) {
      // Case 2: Firebase Storage relative path → convert to GCS URI
      final gcsUri = "gs://$_bucket/$imagePathOrUrl";
      final result = await callable.call({'gcsUri': gcsUri});
      return _extractTextFromCallableResult(result);

    } else {
      // Case 3: local file path
      final file = File(imagePathOrUrl);
      if (!await file.exists()) {
        throw Exception("File not found: $imagePathOrUrl");
      }
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);
      final result = await callable.call({'imageBase64': base64Image});
      return _extractTextFromCallableResult(result);
    }
  }

  String _extractTextFromCallableResult(HttpsCallableResult result) {
    final data = result.data;
    if (data is Map && data['text'] != null) {
      return data['text'] as String;
    }
    if (data is Map && data['fullText'] != null) {
      return data['fullText'] as String;
    }
    return json.encode(data);
  }
}
