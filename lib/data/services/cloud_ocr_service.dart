import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

// Small holder for ranking, moved to top-level.
class _Cand {
  final double value;
  final int score;
  final String line;
  _Cand({required this.value, required this.score, required this.line});
}

class CloudOcrService implements OcrService {
  final HttpsCallable _callable =
      FirebaseFunctions.instance.httpsCallable('parseReceipt');

  OcrResult _parseReceipt(String rawText) {
    final storeName = _extractStoreName(rawText) ?? "Unknown Store";
    final date = _extractDate(rawText) ?? DateTime.now();
    final total = _extractTotal(rawText) ?? 0.0;

    return OcrResult(
      storeName: storeName,
      date: date,
      total: total,
      rawText: rawText,
    );
  }

  @override
  Future<OcrResult> parseImage(String gcsPath) async {
    try {
      final result = await _callable.call<Map<String, dynamic>>({
        // The cloud function expects the GCS path for the image.
        'path': gcsPath,
      });
      final text = result.data['text'] as String? ?? '';
      return _parseReceipt(text);
    } catch (e, s) {
      debugPrint('Failed to call parseReceipt cloud function for image: $e\n$s');
      rethrow;
    }
  }

  @override
  Future<OcrResult> parsePdf(String gcsPath) async {
    // The 'parseReceipt' cloud function uses the GCS URI for PDF processing.
    try {
      final result = await _callable.call<Map<String, dynamic>>({
        // The cloud function expects the GCS path for the PDF.
        'path': gcsPath,
      });
      final text = result.data['text'] as String? ?? '';
      return _parseReceipt(text);
    } catch (e, s) {
      debugPrint('Failed to call parseReceipt cloud function for PDF: $e\n$s');
      rethrow;
    }
  }

  @override
  Future<OcrResult> parseRawText(String rawText) async {
    // No remote calls; just parse the provided text locally.
    try {
      return _parseReceipt(rawText);
    } catch (e, s) {
      debugPrint('Failed to parse raw text: $e\n$s');
      rethrow;
    }
  }

  String? _extractStoreName(String rawText) {
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

  DateTime? _extractDate(String text) {
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
          // Assuming dd/mm/yyyy. For US dates (mm/dd/yyyy) this would need adjustment.
          return DateTime.parse("${parts[2]}-${parts[1]}-${parts[0]}");
        } else if (raw.contains('-')) {
          return DateTime.tryParse(raw);
        }
      } catch (_) {
        // Ignore parsing errors
      }
    }
    return null;
  }

  double? _extractTotal(String text) {
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
    candidates.sort((_Cand b, _Cand a) {
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
}