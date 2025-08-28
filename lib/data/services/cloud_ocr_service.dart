import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

class CloudOcrService implements OcrService {
  final HttpsCallable _callable =
      FirebaseFunctions.instance.httpsCallable('parseReceipt');

  /// Parses the raw text from OCR to extract structured data.
  ///
  /// NOTE: This is a placeholder. A real implementation would use regex or a
  /// more advanced NLP model to extract store name, date, and total amount.
  OcrResult _parseOcrText(String rawText) {
    // TODO: Implement a proper parser to extract structured data.
    // For now, we just return the raw text.
    return OcrResult(rawText: rawText);
  }

  @override
  Future<OcrResult> parseImage(String imageUrl) async {
    try {
      final result = await _callable.call<Map<String, dynamic>>({
        'imageUrl': imageUrl,
      });
      final text = result.data['text'] as String? ?? '';
      return _parseOcrText(text);
    } catch (e, s) {
      debugPrint('Failed to call parseReceipt cloud function: $e\n$s');
      rethrow;
    }
  }

  @override
  Future<OcrResult> parsePdf(String pdfGcsUri) async {
    // The 'parseReceipt' cloud function uses the GCS URI for PDF processing.
    try {
      final result = await _callable.call<Map<String, dynamic>>({
        'pdfGcsUri': pdfGcsUri,
      });
      final text = result.data['text'] as String? ?? '';
      return _parseOcrText(text);
    } catch (e, s) {
      debugPrint('Failed to call parseReceipt cloud function for PDF: $e\n$s');
      rethrow;
    }
  }
}