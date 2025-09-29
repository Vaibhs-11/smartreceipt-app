import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

class ChatGptOcrService implements OcrService {
  final String openAiApiKey;

  ChatGptOcrService({required this.openAiApiKey});

  @override
  Future<OcrResult> parseImage(String imagePathOrUrl) async {
    throw UnimplementedError("Use CloudOcrService for image OCR");
  }

  @override
  Future<OcrResult> parseRawText(String rawText) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    final prompt = """
You are a receipt parser. Extract the following details from this receipt text:
1. Store Name
2. Date of Purchase
3. List of items (name + price)
4. Total amount

Return JSON only:
{
  "storeName": "...",
  "date": "YYYY-MM-DD",
  "items": [{"name": "...", "price": 0.0}],
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
          {"role": "system", "content": "You are a helpful receipt extraction assistant."},
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

    // Safer JSON parse
    Map<String, dynamic> parsed;
    try {
        var cleaned = content.trim();

        // Remove Markdown fences if present
        if (cleaned.startsWith("```")) {
          final firstNewline = cleaned.indexOf('\n');
          final lastFence = cleaned.lastIndexOf("```");
          if (firstNewline != -1 && lastFence != -1) {
            cleaned = cleaned.substring(firstNewline + 1, lastFence).trim();
          }
        }

        parsed = jsonDecode(cleaned);
      } catch (_) {
        throw Exception("Failed to parse JSON from GPT: $content");
      }                         

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
  @override
  Future<OcrResult> parsePdf(String gcsPath) {
    throw UnimplementedError("Use parseRawText after extracting PDF text separately");
  }
}
