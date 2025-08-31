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
  final lines = text.split('\n');
  final candidates = <_Cand>[];

  // Helper: extract all money values from a line and normalize to double
  List<double> _moneyFrom(String s) {
    final moneyRe = RegExp(
      r'(?:AUD\s*)?\$?\s*('
      r'[0-9]{1,3}(?:[.,\s][0-9]{3})*(?:[.,][0-9]{2})' // 1,234.56 or 1 234,56
      r'|[0-9]+[.,][0-9]{2}'                            // 12.34 or 12,34
      r')'
    );
    final out = <double>[];
    for (final m in moneyRe.allMatches(s)) {
      var g = m.group(1)!.replaceAll(' ', '');
      // Normalize thousands vs decimal: use the last separator as decimal
      if (g.contains(',') && g.contains('.')) {
        if (g.lastIndexOf('.') > g.lastIndexOf(',')) {
          g = g.replaceAll(',', '');      // 1,234.56 -> 1234.56
        } else {
          g = g.replaceAll('.', '');      // 1.234,56 -> 1234,56
          g = g.replaceAll(',', '.');     // -> 1234.56
        }
      } else {
        g = g.replaceAll(',', '.');       // 12,34 -> 12.34
      }
      final v = double.tryParse(g);
      if (v != null) out.add(v);
    }
    return out;
  }

  // Pass 1: scan lines, collect candidates with scores
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();

    // Skip common traps
    if (lower.contains('gst') && lower.contains('total')) continue; // e.g., "GST Incl. In Total $14.59"
    if (lower.contains('avail bal') || lower.contains('balance')) continue;
    if (lower.contains('declined')) continue;

    // Score the line by intent
    int score = 0;
    if (lower.contains('grand total')) score += 120;
    if (lower == 'total' || lower.startsWith('total')) score += 110;
    if (lower.contains('amount due')) score += 100;
    if (lower.contains('total')) score += 90;
    if (lower.contains('eftpos') || lower.contains('paid')) score += 70;

    // Extract amounts in this line
    var amounts = _moneyFrom(line);

    // If it's a "total/amount due" line without an amount, look ahead a couple of lines
    if (amounts.isEmpty && (lower.contains('total') || lower.contains('amount due'))) {
      for (int j = 1; j <= 2 && i + j < lines.length; j++) {
        final la = lines[i + j].trim();
        final lal = la.toLowerCase();
        if (lal.isEmpty) continue;
        if (lal.contains('gst') && lal.contains('total')) continue;
        if (lal.contains('balance') || lal.contains('declined')) continue;
        final nextAmts = _moneyFrom(la);
        if (nextAmts.isNotEmpty) {
          amounts = nextAmts;
          break;
        }
      }
    }

    for (final a in amounts) {
      candidates.add(_Cand(value: a, score: score, line: line));
    }
  }

  if (candidates.isNotEmpty) {
    // Prefer higher score; if tie, prefer larger amount
    candidates.sort((b, a) {
      final sc = a.score.compareTo(b.score);
      if (sc != 0) return sc;
      return a.value.compareTo(b.value);
    });
    return candidates.first.value;
  }

  // Final fallback: take the largest money-like number anywhere
  double? best;
  for (final v in _moneyFrom(text)) {
    if (best == null || v > best) best = v;
  }
  return best;
}

// Small holder for ranking
class _Cand {
  final double value;
  final int score;
  final String line;
  _Cand({required this.value, required this.score, required this.line});
}
}
