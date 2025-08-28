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
            {"type": "TEXT_DETECTION"}
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
      throw Exception('Failed to call Vision API: ${response.body}');
    }

    final body = jsonDecode(response.body);
    final textAnnotations = body['responses'][0]['textAnnotations'];
    final rawText = textAnnotations != null && textAnnotations.isNotEmpty
        ? textAnnotations[0]['description']
        : "";

    // Parse OCR text into structured fields (storeName, date, total)
    return _parseReceipt(rawText);
  }

  @override
  Future<OcrResult> parsePdf(String pdfPath) async {
    // For PDFs you would need to convert pages to images first
    throw UnimplementedError("PDF OCR not yet implemented.");
  }

  OcrResult _parseReceipt(String rawText) {
    // Very basic parsing logic — refine this later
    final storeName = rawText.split("\n").first;
    final date = DateTime.now(); // TODO: extract real date with regex
    final total = 0.0; // TODO: extract using regex
    return OcrResult(
        storeName: storeName,
        date: date,
        total: total,
        rawText: rawText);
  }
}
