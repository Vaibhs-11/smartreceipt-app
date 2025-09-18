import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

class GoogleVisionOcrService implements OcrService {
  final String apiKey;

  GoogleVisionOcrService(this.apiKey);

  @override
Future<OcrResult> parseImage(String imagePathOrUrl) async {
  final url = Uri.parse(
    'https://vision.googleapis.com/v1/images:annotate?key=$apiKey',
  );

  Map<String, dynamic> imagePayload;

  if (imagePathOrUrl.startsWith('http')) {
    // Remote file (Firebase Storage download URL)
    imagePayload = {
      "source": {"imageUri": imagePathOrUrl}
    };
  } else {
    // Local file path
    final file = File(imagePathOrUrl);
    if (!await file.exists()) {
      throw Exception('Local file not found: $imagePathOrUrl');
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

  // Place this in the same file as your other helpers
double? extractTotal(String text, {bool debug = false}) {
  final lines = text.split('\n');

  // Normalizer & extractor: returns a list of doubles found in a line
  List<double> _moneyFrom(String s) {
    final moneyRe = RegExp(
      r'(?:AUD\s*|\$)?\s*('
      r'[0-9]{1,3}(?:[.,\s][0-9]{3})*(?:[.,][0-9]{2})' // 1,234.56 or 1 234,56
      r'|[0-9]+(?:[.,][0-9]{2})'                       // 12.34 or 12,34
      r')'
    );
    final out = <double>[];
    for (final m in moneyRe.allMatches(s)) {
      var g = m.group(1)!.replaceAll(' ', '');
      // Decide last separator is decimal separator
      if (g.contains(',') && g.contains('.')) {
        if (g.lastIndexOf('.') > g.lastIndexOf(',')) {
          g = g.replaceAll(',', ''); // 1,234.56 -> 1234.56
        } else {
          g = g.replaceAll('.', ''); // 1.234,56 -> 1234,56
          g = g.replaceAll(',', '.'); // -> 1234.56
        }
      } else {
        g = g.replaceAll(',', '.'); // 12,34 -> 12.34
      }
      final v = double.tryParse(g);
      if (v != null) out.add(v);
    }
    return out;
  }

  // Weighted keyword map (higher = stronger signal the line is a total)
  final keywordWeights = <String, int>{
    'grand total': 200,
    'invoice total': 180,
    'amount due': 170,
    'amount payable': 170,
    'total': 160,
    'subtotal': 120,
    'paid': 110,
    'eftpos': 100,
    'payment': 100,
    'balance due': 140,
  };

  final candidates = <_Cand>[];

  // Collect all money-like tokens across the document for debug/fallback
  final allMoney = <_MoneyMatch>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final matches = _moneyFrom(line);
    for (final m in matches) {
      allMoney.add(_MoneyMatch(value: m, lineIndex: i, lineText: line.trim()));
    }
  }

  if (debug) {
    print('--- Money tokens found (${allMoney.length}) ---');
    for (final m in allMoney) {
      print('line ${m.lineIndex}: ${m.value.toStringAsFixed(2)} -> "${m.lineText}"');
    }
  }

  // 1) Look for explicit keywords and capture amounts in the same or close lines
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();

    // Skip obvious traps where "total" is for tax only
    if (lower.contains('gst') && lower.contains('total')) continue;
    if (lower.contains('tax') && lower.contains('total')) continue;
    if (lower.contains('change') || lower.contains('refun')) continue; // refund/change

    // Determine best keyword present in the line (longer phrases first)
    int bestWeight = 0;
    for (final key in keywordWeights.keys) {
      if (lower.contains(key)) {
        if (keywordWeights[key]! > bestWeight) bestWeight = keywordWeights[key]!;
      }
    }

    // If keyword hit, attempt to find amounts in same line, or up to 3 lines ahead/back
    if (bestWeight > 0) {
      var amounts = _moneyFrom(line);

      // look ahead/back if no amounts in same line
      if (amounts.isEmpty) {
        // search nearby lines (backwards 2 lines, forwards 3 lines)
        for (int j = 1; j <= 2 && i - j >= 0 && amounts.isEmpty; j++) {
          final la = lines[i - j].trim();
          if (la.isEmpty) continue;
          if (la.toLowerCase().contains('gst') && la.toLowerCase().contains('total')) continue;
          amounts = _moneyFrom(la);
        }
        for (int j = 1; j <= 3 && i + j < lines.length && amounts.isEmpty; j++) {
          final la = lines[i + j].trim();
          if (la.isEmpty) continue;
          if (la.toLowerCase().contains('gst') && la.toLowerCase().contains('total')) continue;
          amounts = _moneyFrom(la);
        }
      }

      for (final a in amounts) {
        candidates.add(_Cand(value: a, score: bestWeight, lineIndex: i, line: line));
      }
    }
  }

  // 2) If no keyword-based candidates, check bottom region of receipt (last N lines)
  if (candidates.isEmpty) {
    final N = 12; // look at last 12 lines
    final start = (lines.length - N).clamp(0, lines.length);
    for (int i = start; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      // skip small balance lines or "AVAIL BAL" style
      final lower = line.toLowerCase();
      if (lower.contains('avail bal') || lower.contains('available balance')) continue;
      if (lower.contains('gst') && lower.contains('total')) continue;

      final amounts = _moneyFrom(line);
      for (final a in amounts) {
        // give modest weight to bottom-of-receipt matches
        candidates.add(_Cand(value: a, score: 75, lineIndex: i, line: line));
      }
    }
  }

  if (debug) {
    print('--- Candidate totals before ranking (${candidates.length}) ---');
    for (final c in candidates) {
      print('score=${c.score} value=${c.value.toStringAsFixed(2)} lineIdx=${c.lineIndex} -> "${c.line}"');
    }
  }

  // Rank candidates: higher score first, then larger value
  if (candidates.isNotEmpty) {
    candidates.sort((b, a) {
      final sc = a.score.compareTo(b.score);
      if (sc != 0) return sc;
      return a.value.compareTo(b.value);
    });
    final chosen = candidates.first;
    if (debug) {
      print('>>> selected candidate: value=${chosen.value}, score=${chosen.score}, line="${chosen.line}"');
    }
    return chosen.value;
  }

  // Final fallback: pick the largest money token anywhere
  double? best;
  for (final m in allMoney) {
    if (best == null || m.value > best) best = m.value;
  }
  if (debug) {
    print('>>> fallback largest token: ${best?.toStringAsFixed(2) ?? "none"}');
  }
  return best;
}

// Helper holders
class _Cand {
  final double value;
  final int score;
  final int lineIndex;
  final String line;
  _Cand({required this.value, required this.score, required this.lineIndex, required this.line});
}
class _MoneyMatch {
  final double value;
  final int lineIndex;
  final String lineText;
  _MoneyMatch({required this.value, required this.lineIndex, required this.lineText});
}

