import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

class ChatGptOcrService implements OcrService {
  final String openAiApiKey;
  final String googleVisionApiKey;

  ChatGptOcrService(this.openAiApiKey, this.googleVisionApiKey);

  /// Handles IMAGE receipts (Vision OCR → GPT)
  @override
  Future<OcrResult> parseImage(String imagePathOrUrl) async {
    final rawText = await _getTextFromImage(imagePathOrUrl);
    return _parseWithOpenAI(rawText);
  }

  /// Handles PDF receipts (if you still want a placeholder)
  @override
  Future<OcrResult> parsePdf(String pdfPath) async {
    throw UnimplementedError(
      "Use parseRawText() after extracting PDF text separately."
    );
  }

  /// Handles already-extracted raw text (from PDF or elsewhere)
  Future<OcrResult> parseRawText(String rawText) async {
    return _parseWithOpenAI(rawText);
  }

  /// --- Google Vision OCR Helper ---
  Future<String> _getTextFromImage(String imagePathOrUrl) async {
    final url = Uri.parse(
      'https://vision.googleapis.com/v1/images:annotate?key=$googleVisionApiKey',
    );

    Map<String, dynamic> imagePayload;

    if (imagePathOrUrl.startsWith('http')) {
      imagePayload = {
        "source": {"imageUri": imagePathOrUrl}
      };
    } else {
      final file = File(imagePathOrUrl);
      if (!await file.exists()) {
        throw Exception('File not found: $imagePathOrUrl');
      }
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);
      imagePayload = {"content": base64Image};
    }

    final requestPayload = {
      "requests": [
        {
          "image": imagePayload,
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

    return responses[0]['fullTextAnnotation']?['text'] ??
        (responses[0]['textAnnotations']?[0]?['description'] ?? "");
  }

  /// --- OpenAI Parsing Helper ---
  Future<OcrResult> _parseWithOpenAI(String rawText) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    final prompt = """
You are a receipt parser. Extract the following details from this receipt text:
1. Store Name
2. Date of Purchase
3. List of all items purchased and their cost
4. Total Bill Value

Return the answer strictly in JSON with this format:
{
  "storeName": "...",
  "date": "YYYY-MM-DD",
  "items": [
    {"name": "...", "price": 0.0}
  ],
  "total": 0.0
}

Receipt Text:
$rawText
""";

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $openAiApiKey",
      },
      body: jsonEncode({
        "model": "gpt-4o-mini",
        "messages": [
          {
            "role": "system",
            "content": "You are a helpful receipt extraction assistant."
          },
          {"role": "user", "content": prompt}
        ],
        "temperature": 0,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("OpenAI API error: ${response.body}");
    }

    final body = jsonDecode(response.body);
    final content = body["choices"][0]["message"]["content"];

    final parsed = jsonDecode(content);

    return OcrResult(
        storeName: parsed["storeName"] ?? "Unknown Store",
        date: DateTime.tryParse(parsed["date"] ?? "") ?? DateTime.now(),
        total: (parsed["total"] ?? 0).toDouble(),
        rawText: rawText,
        items: (parsed["items"] as List<dynamic>?)
                ?.map((e) => OcrReceiptItem(
                        name: e["name"] ?? "",
                        price: (e["price"] ?? 0).toDouble(),
                    ))
                .toList() ??
            [],
        );
  }
}
