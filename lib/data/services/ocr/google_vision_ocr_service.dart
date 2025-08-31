import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

class GoogleVisionOcrService implements OcrService {
  final String apiKey;

  GoogleVisionOcrService(this.apiKey);

  @override
  Future<OcrResult> parseImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);

    final url = Uri.parse(
      'https://vision.googleapis.com/v1/images:annotate?key=$apiKey',
    );

    final requestPayload = {
      "requests": [
        {
          "image": {"content": base64Image},
          "features": [
            {"type": "DOCUMENT_TEXT_DETECTION"}
          ]
        }
      ]
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(requestPayload),
    );

    if (response.statusCode != 200) {
      throw Exception('Vision API error: ${response.body}');
    }

    final body = jsonDecode(response.body);
    final responses = body['responses'] as List?;
    if (responses == null || responses.isEmpty) {
      throw Exception('No OCR response from Vision API');
    }

    // Prefer fullTextAnnotation for receipts
    final rawText = responses[0]['fullTextAnnotation']?['text'] ??
        (responses[0]['textAnnotations']?[0]?['description'] ?? "");

    return _parseReceipt(rawText);
  }

  @override
  Future<OcrResult> parsePdf(String pdfPath) async {
    throw UnimplementedError("PDF OCR not yet implemented.");
  }

  /// --- Receipt Parsing Logic ---
  OcrResult _parseReceipt(String rawText) {
    final storeName = extractStoreName(rawText) ?? "Unknown Store";
    final date = extractDate(rawText) ?? DateTime.now();
    final total = extractTotal(rawText) ?? 0.0;

    return OcrResult(
      storeName: storeName,
      date: date,
      total: total,
      rawText: rawText,
    );
  }

  String? extractStoreName(String rawText) {
    final lines = rawText.split("\n");

    for (var line in lines.take(5)) {
      final cleaned = line.trim();
      if (cleaned.isEmpty) continue;

      // Skip dates
      final dateRegex = RegExp(r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})');
      if (dateRegex.hasMatch(cleaned)) continue;

      // Skip totals
      final totalRegex =
          RegExp(r'(total|amount|balance|cash|change)', caseSensitive: false);
      if (totalRegex.hasMatch(cleaned)) continue;

      // Skip phone numbers
      final phoneRegex = RegExp(r'(\+?\d[\d\s-]{5,})');
      if (phoneRegex.hasMatch(cleaned)) continue;

      // Skip ABN/GST
      final abnRegex = RegExp(r'(ABN|GST)', caseSensitive: false);
      if (abnRegex.hasMatch(cleaned)) continue;

      return cleaned; // Assume store name
    }
    return null;
  }

  DateTime? extractDate(String text) {
    final dateRegex = RegExp(
      r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})',
    );
    final match = dateRegex.firstMatch(text);
    if (match != null) {
      final raw = match.group(0)!;
      // Normalize dd/mm/yyyy -> yyyy-mm-dd if possible
      try {
        if (raw.contains('/')) {
          final parts = raw.split('/');
          if (parts[2].length == 2) {
            // expand yy -> yyyy (naive assumption: 20xx)
            parts[2] = "20${parts[2]}";
          }
          return DateTime.parse("${parts[2]}-${parts[1]}-${parts[0]}");
        } else if (raw.contains('-')) {
          return DateTime.tryParse(raw);
        }
      } catch (_) {}
    }
    return null;
  }

  double? extractTotal(String text) {
    final totalRegex =
        RegExp(r'((TOTAL|AMOUNT|BALANCE)[^\d]*)(\d+[.,]\d{2})',
            caseSensitive: false);
    final match = totalRegex.firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(3)!.replaceAll(',', '.'));
    }

    // fallback: grab last number with decimals
    final fallbackRegex = RegExp(r'\d+[.,]\d{2}');
    final matches = fallbackRegex.allMatches(text);
    if (matches.isNotEmpty) {
      return double.tryParse(matches.last.group(0)!.replaceAll(',', '.'));
    }
    return null;
  }
}
