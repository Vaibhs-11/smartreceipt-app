// lib/data/services/ocr/chatgpt_ocr_service.dart
import 'dart:convert';
import 'dart:math';
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
  Future<OcrResult> parsePdf(String gcsPath) {
    throw UnimplementedError("Use parseRawText after extracting PDF text separately");
  }

  @override
  Future<OcrResult> parseRawText(String rawText) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    // Improved prompt: be strict, do not round, include currency and candidate totals.
    final prompt = """
You are a strict receipt parser. Extract these exact values from the receipt text below.
- storeName: primary store name (top of receipt).
- date: purchase date in YYYY-MM-DD format.
- items: list of item objects with exact item name and exact numeric price (use decimals as shown).
- total: the exact final total amount that is the bill value (do not round or "guess" — pick the amount that is clearly labelled TOTAL, Grand Total, Invoice Total, or the final billed amount).
- currency: currency code (e.g. AUD, USD, GBP) if present. If not present, try to infer from the receipt (domain .au -> AUD, presence of 'GST' or 'ABN' -> AUD, 'HST' -> CAD, etc).
- ALSO return a list named 'totals' containing candidate amounts with their context text, and indicate which candidate you selected using 'selectedTotalIndex' (0-based). This helps downstream validation.

Rules:
- If a currency symbol (AUD, A\$, \$, USD, EUR, etc.) is present, use it.
- If only "\$" is shown, infer the local currency of the store’s country.
- If the receipt mentions an Australian store/location (e.g. Myer, Coles, Woolworths, ABN, .com.au, etc.), default to AUD.
- Never assume USD unless the receipt explicitly mentions USD.
- Preserve cents exactly as written.

Return JSON only, no markdown fences, no other text. Example response format:

{
  "storeName": "Example Store",
  "date": "2025-08-17",
  "items": [
    {"name": "ITEM A", "price": 12.34},
    {"name": "ITEM B", "price": 5.00}
  ],
  "totals": [
    {"label": "TOTAL", "amount": 17.34, "context": "TOTAL\\n\$17.34"},
    {"label": "Paid", "amount": 17.00, "context": "Paid\\n\$17.00"}
  ],
  "selectedTotalIndex": 0,
  "total": 17.34,
  "currency": "AUD"
}

Important instructions for the model:
- Do not round any amounts; return them exactly as numbers with decimals when shown.
- If multiple "totals" exist, prefer the one explicitly labelled TOTAL, GRAND TOTAL, or the one on the 'TOTAL' line. If still ambiguous, prefer the amount that represents the final billed amount (not a partial refund or "Paid" rounding).
- If you cannot find a date in YYYY-MM-DD, try to parse dd/mm/yyyy, dd/mm/yy and convert it to YYYY-MM-DD. If unable to parse, return an empty string for date.
- If currency is missing, you may leave it empty; the client will try to infer from the receipt text.

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
          {"role": "system", "content": "You are a precise JSON-producing receipt parser."},
          {"role": "user", "content": prompt}
        ],
        "temperature": 0,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("OpenAI API error: ${response.body}");
    }

    final body = jsonDecode(response.body);
    final content = body["choices"]?[0]?["message"]?["content"]?.toString() ?? "";

    // Clean fences and markdown, then parse JSON
    final cleaned = _cleanModelContent(content);

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw Exception("Failed to parse JSON from GPT: $content");
    }

    // Extract values from parsed JSON
    final storeName = (parsed["storeName"] as String?)?.trim();
    final rawDate = (parsed["date"] as String?) ?? "";
    final parsedDate = _tryParseDate(rawDate);
    final parsedCurrency = (parsed["currency"] as String?)?.trim();

    // Items
    List<OcrReceiptItem> items = [];
    if (parsed["items"] is List) {
      for (final e in parsed["items"] as List) {
        if (e is Map) {
          final name = (e["name"] ?? "").toString();
          final priceNum = _numFromDynamic(e["price"]);
          items.add(OcrReceiptItem(name: name, price: priceNum ?? 0.0));
        }
      }
    }

    // Get GPT-proposed total(s)
    double? gptTotal = _numFromDynamic(parsed["total"]);
    // Also allow selectedTotalIndex/totals structure
    double? gptSelectedTotal;
    if (parsed["selectedTotalIndex"] != null && parsed["totals"] is List) {
      final idx = (parsed["selectedTotalIndex"] as num).toInt();
      final totals = parsed["totals"] as List;
      if (idx >= 0 && idx < totals.length) {
        gptSelectedTotal = _numFromDynamic((totals[idx] as Map)["amount"]);
      }
    }

    // Choose the best GPT total (prefer explicit selectedTotalIndex)
    final gptChosen = gptSelectedTotal ?? gptTotal;

    // Local heuristic extraction (fallback / cross-check)
    final localTotal = _localExtractTotal(rawText);

    // Decide final total: prefer local if GPT missing or significantly different
    double finalTotal;
    if (gptChosen == null && localTotal != null) {
      finalTotal = localTotal;
    } else if (gptChosen != null && localTotal == null) {
      finalTotal = gptChosen;
    } else if (gptChosen != null && localTotal != null) {
      // If the difference is small (< 0.01) accept GPT, otherwise prefer the local extraction
      if ((gptChosen - localTotal).abs() < 0.01) {
        finalTotal = gptChosen;
      } else {
        // pick localTotal because it's likely the 'TOTAL' extracted from receipt layout
        finalTotal = localTotal;
      }
    } else {
      finalTotal = (gptChosen ?? 0.0);
    }

    // Determine currency: prefer GPT; if missing, infer from rawText
    final currency = _inferCurrency(rawText, parsedCurrency);

    return OcrResult(
      storeName: storeName ?? "Unknown Store",
      date: parsedDate ?? DateTime.now(),
      total: finalTotal,
      rawText: rawText,
      items: items,
      currency: currency,
    );
  }

  // ---------------- Helper utils ----------------

  /// Remove markdown fences and leading/trailing text commonly returned by model
  String _cleanModelContent(String content) {
    var s = content.trim();

    // strip triple backtick fences, optionally with language e.g. ```json
    if (s.startsWith('```')) {
      // find first newline after opening fence
      final firstNewline = s.indexOf('\n');
      final lastFence = s.lastIndexOf('```');
      if (firstNewline != -1 && lastFence != -1 && lastFence > firstNewline) {
        s = s.substring(firstNewline + 1, lastFence).trim();
      }
    }

    // If wrapped in single backticks or other wrappers, attempt to strip common wrappers
    s = s.trim();
    return s;
  }

  double? _numFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^\d\.,\-]'), '').trim();
      if (cleaned.isEmpty) return null;
      // Decide decimal separator
      String t = cleaned;
      if (t.contains(',') && t.contains('.')) {
        // assume last dot or comma is decimal
        if (t.lastIndexOf('.') > t.lastIndexOf(',')) {
          t = t.replaceAll(',', '');
        } else {
          t = t.replaceAll('.', '');
          t = t.replaceAll(',', '.');
        }
      } else {
        t = t.replaceAll(',', '.');
      }
      return double.tryParse(t);
    }
    return null;
  }

  DateTime? _tryParseDate(String s) {
    if (s.trim().isEmpty) return null;
    // Try ISO first
    try {
      final iso = DateTime.tryParse(s);
      if (iso != null) return iso;
    } catch (_) {}
    // Try dd/mm/yyyy or dd/mm/yy
    final dm = RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})');
    final m = dm.firstMatch(s);
    if (m != null) {
      try {
        final d = int.parse(m.group(1)!);
        final mo = int.parse(m.group(2)!);
        var y = m.group(3)!;
        var yi = int.parse(y);
        if (y.length == 2) {
          yi += (yi >= 70 ? 1900 : 2000); // naive 2-digit year handling
        }
        return DateTime(yi, mo, d);
      } catch (_) {}
    }
    // Last resort: try to locate yyyy-mm-dd inside
    final isoRe = RegExp(r'(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})');
    final m2 = isoRe.firstMatch(s);
    if (m2 != null) {
      try {
        final y = int.parse(m2.group(1)!);
        final mo = int.parse(m2.group(2)!);
        final d = int.parse(m2.group(3)!);
        return DateTime(y, mo, d);
      } catch (_) {}
    }
    return null;
  }

  /// Heuristic local extraction of "total" from receipt rawText.
  /// Looks for lines with money values and boosts lines containing keywords.
  double? _localExtractTotal(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    // money regex captures amounts like 1,234.56 or 1234,56 or 12.34
    final moneyRe = RegExp(r'(?:AUD\s*|\$)?\s*([0-9]{1,3}(?:[.,\s][0-9]{3})*(?:[.,][0-9]{2})|[0-9]+(?:[.,][0-9]{2}))');
    final keywordWeights = {
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
    final allMoney = <_MoneyMatch>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      for (final m in moneyRe.allMatches(line)) {
        var g = m.group(1)!.replaceAll(' ', '');
        if (g.contains(',') && g.contains('.')) {
          if (g.lastIndexOf('.') > g.lastIndexOf(',')) {
            g = g.replaceAll(',', '');
          } else {
            g = g.replaceAll('.', '');
            g = g.replaceAll(',', '.');
          }
        } else {
          g = g.replaceAll(',', '.');
        }
        final v = double.tryParse(g);
        if (v != null) {
          allMoney.add(_MoneyMatch(value: v, lineIndex: i, lineText: line));
        }
      }
    }

    // collect keyword candidates
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();

      // skip obvious traps
      if ((lower.contains('gst') && lower.contains('total')) ||
          lower.contains('avail bal') ||
          lower.contains('available balance')) {
        continue;
      }

      int bestWeight = 0;
      for (final key in keywordWeights.keys) {
        if (lower.contains(key)) {
          bestWeight = max(bestWeight, keywordWeights[key]!);
        }
      }

      if (bestWeight > 0) {
        // look for amounts in same line or near lines
        var amounts = <double>[];
        for (final m in moneyRe.allMatches(line)) {
          var g = m.group(1)!.replaceAll(' ', '');
          if (g.contains(',') && g.contains('.')) {
            if (g.lastIndexOf('.') > g.lastIndexOf(',')) g = g.replaceAll(',', '');
            else {
              g = g.replaceAll('.', '');
              g = g.replaceAll(',', '.');
            }
          } else {
            g = g.replaceAll(',', '.');
          }
          final v = double.tryParse(g);
          if (v != null) amounts.add(v);
        }
        // if none, search nearby lines for an amount
        if (amounts.isEmpty) {
          for (int j = 1; j <= 3 && (i + j) < lines.length && amounts.isEmpty; j++) {
            final la = lines[i + j].trim();
            if (la.isEmpty) continue;
            for (final m in moneyRe.allMatches(la)) {
              var g = m.group(1)!.replaceAll(' ', '');
              if (g.contains(',') && g.contains('.')) {
                if (g.lastIndexOf('.') > g.lastIndexOf(',')) g = g.replaceAll(',', '');
                else {
                  g = g.replaceAll('.', '');
                  g = g.replaceAll(',', '.');
                }
              } else {
                g = g.replaceAll(',', '.');
              }
              final v = double.tryParse(g);
              if (v != null) amounts.add(v);
            }
          }
        }
        for (final a in amounts) {
          candidates.add(_Cand(value: a, score: bestWeight, line: line));
        }
      }
    }

    // bottom-of-receipt fallback (last N lines)
    if (candidates.isEmpty) {
      final N = 12;
      final start = max(0, lines.length - N);
      for (int i = start; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final lower = line.toLowerCase();
        if (lower.contains('avail bal') || lower.contains('available balance')) continue;
        for (final m in moneyRe.allMatches(line)) {
          var g = m.group(1)!.replaceAll(' ', '');
          if (g.contains(',') && g.contains('.')) {
            if (g.lastIndexOf('.') > g.lastIndexOf(',')) g = g.replaceAll(',', '');
            else {
              g = g.replaceAll('.', '');
              g = g.replaceAll(',', '.');
            }
          } else {
            g = g.replaceAll(',', '.');
          }
          final v = double.tryParse(g);
          if (v != null) candidates.add(_Cand(value: v, score: 75, line: line));
        }
      }
    }

    if (candidates.isNotEmpty) {
      candidates.sort((b, a) {
        final sc = a.score.compareTo(b.score);
        if (sc != 0) return sc;
        return a.value.compareTo(b.value);
      });
      return candidates.first.value;
    }

    // final fallback: pick largest money token
    double? best;
    for (final m in allMoney) {
      if (best == null || m.value > best) best = m.value;
    }
    return best;
  }

  /// Infer currency code from receipt text or parsed currency. Attempts a few heuristics.
  String _inferCurrency(String rawText, String? parsedCurrency) {
    if (parsedCurrency != null && parsedCurrency.trim().isNotEmpty) {
      return parsedCurrency.toUpperCase();
    }

    final lower = rawText.toLowerCase();

    // Explicit currency codes
    final codeRe = RegExp(r'\b(AUD|USD|GBP|EUR|CAD|NZD|SGD|INR|JPY|CNY)\b', caseSensitive: false);
    final cm = codeRe.firstMatch(rawText);
    if (cm != null) return cm.group(1)!.toUpperCase();

    // Domain hints
    if (lower.contains('.au') || lower.contains('myer.com.au') || lower.contains('abn')) return 'AUD';
    if (lower.contains('.co.nz') || lower.contains('.nz')) return 'NZD';
    if (lower.contains('.ca') || lower.contains('gst/hst') || lower.contains('hst')) return 'CAD';
    if (lower.contains('£') || lower.contains('pound')) return 'GBP';
    if (lower.contains('eur') || lower.contains('€')) return 'EUR';
    if (lower.contains('sgd') || lower.contains('.sg')) return 'SGD';
    if (lower.contains('inr') || RegExp(r'\bINR\b', caseSensitive: false).hasMatch(rawText)) return 'INR';
    if (lower.contains('cny') || lower.contains('¥') && lower.contains('cn')) return 'CNY';

    // GST without country -> likely Australia
    if (lower.contains('gst') || lower.contains('abn')) return 'AUD';

    // Fallback: USD (if we cannot infer)
    return 'USD';
  }
}

// Small helper classes used above
class _Cand {
  final double value;
  final int score;
  final String line;
  _Cand({required this.value, required this.score, required this.line});
}

class _MoneyMatch {
  final double value;
  final int lineIndex;
  final String lineText;
  _MoneyMatch({required this.value, required this.lineIndex, required this.lineText});
}
