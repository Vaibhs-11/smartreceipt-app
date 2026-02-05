// lib/data/services/ocr/chatgpt_ocr_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:receiptnest/domain/entities/ocr_result.dart';
import 'package:receiptnest/domain/services/ocr_service.dart';

class ChatGptOcrService implements OcrService {
  final String openAiApiKey;
  static Future<String?>? _cachedAppVersion;

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

    // Improved prompt: be strict, do not round, include currency, candidate totals, enrichment metadata,
    // a hard classification flag for whether the content is a receipt, and safe handling for discounts.
    final prompt = """
You are a strict receipt parser.

Your task is to extract structured data from the receipt text below.
Be precise, conservative, and deterministic.

────────────────────────────────────────
REQUIRED FIELDS
────────────────────────────────────────

Extract these exact values:

- isReceipt:
  boolean.
  Set true ONLY when the text represents a purchase receipt or tax invoice.
  If the text is unrelated (bank statement, invoice without purchase items,
  tickets, ads, random text, emails), set false.

- receiptRejectionReason:
  short explanation ONLY when isReceipt is false
  (e.g. "bank statement, not a purchase receipt").
  Keep it concise.
  Set null when isReceipt is true.

- storeName:
  primary store name (typically at the top of the receipt).

- date:
  purchase date in YYYY-MM-DD format.
  If not already in this format, try parsing dd/mm/yyyy or dd/mm/yy.
  If unable to determine a date, return an empty string.

- items:
  list of item objects.
  Each item must include:
    - name: exact item name as shown on the receipt
    - price: exact numeric price (preserve decimals exactly as written) OR null when uncertain
    - priceConfidence: "high" or "low"
      * "low" when price is missing/ambiguous, near discounts/negative amounts, or uncertain
      * default to "high" only when a clear positive price is paired with the item name

  Rules for discounts / negative amounts:
    - Negative values (e.g., "-3.00", "3.00-", "LESS 3.00") are adjustments/discounts.
    - Never assign negative values as an item's unit price.
    - If only a negative/discount value is near an item, set price to null and priceConfidence to "low".
    - Do NOT guess prices. Do NOT backfill prices from totals or other sections.

- total:
  the exact final billed amount.
  Choose the amount explicitly labelled TOTAL, GRAND TOTAL,
  INVOICE TOTAL, or the final amount payable.
  Do NOT round.
  Do NOT guess.

- totals:
  list of candidate totals with context.
  Each entry must include:
    - label
    - amount
    - context (the receipt line or nearby text)

- selectedTotalIndex:
  0-based index into the totals array indicating which total you selected.

- currency:
  currency code (e.g. AUD, USD, GBP).
  If missing, try to infer from context:
    - .au domain, ABN, GST → AUD
    - HST → CAD
  Never assume USD unless explicitly stated.

────────────────────────────────────────
RECEIPT-LEVEL ENRICHMENT (SEARCH METADATA)
────────────────────────────────────────

Additionally, derive these receipt-level metadata fields.
These are used ONLY for search enrichment, not for financial accuracy.

You must be conservative, but you MAY use widely known consumer product knowledge
when confidence is high.

- normalizedBrand:
  The most likely brand name, corrected for OCR errors.
  You MAY normalize when the text strongly implies a known brand.
  Examples:
    - "BRAU" → "Braun"
    - "Playstation" → "Sony"
  Return null if not reasonably confident.

- category:
  A concrete, high-level product type.
  Prefer specific product types over generic categories.

  Examples of preferred categories:
    - "coffee machine"
    - "espresso machine"
    - "gaming console"
    - "electric shaver"
    - "groceries"
    - "clothing"

  You MAY use widely known consumer product knowledge when the
  brand + product line strongly imply the product type.
  Examples:
    - Breville "Oracle" → coffee machine / espresso machine
    - Sony "PlayStation" → gaming console
    - Braun "Series 9" → electric shaver

  Return null ONLY when the product type cannot be reasonably inferred.

- searchKeywords:
  A list of lowercased keywords useful for search.
  These keywords should reflect how a user would naturally search.

  Include:
    - normalized brand (if available)
    - product family or model (e.g. "oracle", "series 9", "ps5")
    - inferred product type
    - common user intent synonyms when strongly implied
      (e.g. "coffee machine", "espresso machine", "gaming console")

  Rules:
    - You MAY include keywords even if the exact words are not printed,
      as long as they are strongly implied by the product.
    - Do NOT invent facts.
    - Do NOT include duplicates.
    - Lowercase all keywords.
    - Prefer singular nouns (e.g. "coffee machine", not "coffee machines").

────────────────────────────────────────
IMPORTANT RULES
────────────────────────────────────────

- Do NOT round any monetary amounts.
- Preserve cents exactly as written.
- Never invent prices, brands, or products.
- If multiple totals exist, prefer the one clearly labelled TOTAL or equivalent.
- If the content is not a receipt:
    - set isReceipt to false
    - provide receiptRejectionReason
    - keep monetary fields at 0 and strings empty where unsure

────────────────────────────────────────
OUTPUT FORMAT
────────────────────────────────────────

Return JSON ONLY.
No markdown.
No explanations.
No extra text.

Example response format:

{
  "isReceipt": true,
  "receiptRejectionReason": null,
  "storeName": "Example Store",
  "date": "2025-08-17",
  "items": [
    { "name": "ITEM A", "price": 12.34, "priceConfidence": "high" },
    { "name": "ITEM B", "price": null, "priceConfidence": "low" }
  ],
  "totals": [
    { "label": "TOTAL", "amount": 17.34, "context": "TOTAL\n\$17.34" },
    { "label": "Paid", "amount": 17.00, "context": "Paid\n\$17.00" }
  ],
  "selectedTotalIndex": 0,
  "total": 17.34,
  "currency": "AUD",
  "normalizedBrand": "Breville",
  "category": "coffee machine",
  "searchKeywords": [
    "breville",
    "oracle",
    "coffee machine",
    "espresso machine"
  ]
}
────────────────────────────────────────
RECEIPT TEXT
────────────────────────────────────────
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
    final bool isReceipt = _parseBool(parsed["isReceipt"]) ?? true;
    final rejectionReason = _normalizeOptionalString(
      parsed["receiptRejectionReason"] as String?,
    );
    final storeName = (parsed["storeName"] as String?)?.trim();
    final rawDate = (parsed["date"] as String?) ?? "";
    final parsedDate = _tryParseDate(rawDate);
    final parsedCurrency = (parsed["currency"] as String?)?.trim();
    final normalizedBrand = _normalizeOptionalString(
      parsed["normalizedBrand"] as String?,
    );
    final category = _normalizeOptionalString(
      parsed["category"] as String?,
    );

    final searchKeywords = _extractSearchKeywords(parsed["searchKeywords"]);

    // Items
    List<OcrReceiptItem> items = [];
    if (parsed["items"] is List) {
      for (final e in parsed["items"] as List) {
        if (e is Map) {
          final name = (e["name"] ?? "").toString();
          double? priceNum = _numFromDynamic(e["price"]);
          var priceConfidenceRaw = (e["priceConfidence"] ?? "").toString().toLowerCase();
          var priceConfidence = priceConfidenceRaw == "low" ? "low" : "high";

          // Treat negative or missing values as low confidence/null prices.
          if (priceNum != null && priceNum < 0) {
            priceNum = null;
            priceConfidence = "low";
          }
          if (priceNum == null && priceConfidence == "high") {
            priceConfidence = "low";
          }

          items.add(
            OcrReceiptItem(
              name: name,
              price: priceNum,
              priceConfidence: priceConfidence,
            ),
          );
        }
      }
    }

    final int itemCountBeforeFilter = items.length;

    // Drop OCR artefacts that have no amount or a non-positive amount.
    items = items
        .where((item) => item.price != null && item.price! > 0)
        .toList();

    final int itemCountAfterFilter = items.length;

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

    // Ensure normalized brand / category keywords appear in search keywords
    void ensureKeyword(String? value) {
      final normalized = value?.trim().toLowerCase();
      if (normalized == null || normalized.isEmpty) return;
      if (!searchKeywords.contains(normalized)) {
        searchKeywords.add(normalized);
      }
    }

    ensureKeyword(normalizedBrand);
    ensureKeyword(category);

    if (!isReceipt) {
      final appVersion = await _getAppVersion();
      final preview = rawText.length > 400 ? rawText.substring(0, 400) : rawText;
      // Find these logs in Firebase Console → Crashlytics → Logs.
      FirebaseCrashlytics.instance.log(
        'RECEIPT_REJECTED ${jsonEncode({
          "platform": Platform.operatingSystem,
          "appVersion": appVersion,
          "ocrTextLength": rawText.length,
          "ocrTextPreview": preview,
          "receiptRejectionReason": rejectionReason,
          "itemCountBeforeFilter": itemCountBeforeFilter,
          "itemCountAfterFilter": itemCountAfterFilter,
          "gptTotal": gptChosen,
          "localExtractedTotal": localTotal,
          "currency": currency,
        })}',
      );
      FirebaseCrashlytics.instance.recordError(
        Exception('RECEIPT_REJECTED'),
        StackTrace.current,
       fatal: false,
      );
    }

    return OcrResult(
      storeName: storeName ?? "Unknown Store",
      date: parsedDate ?? DateTime.now(),
      total: finalTotal,
      rawText: rawText,
      items: items,
      isReceipt: isReceipt,
      receiptRejectionReason: rejectionReason,
      currency: currency,
      searchKeywords: searchKeywords,
      normalizedBrand: normalizedBrand,
      category: category,
    );
  }

  static Future<String?> _getAppVersion() {
    _cachedAppVersion ??=
        PackageInfo.fromPlatform().then((info) => info.version).catchError((_) {
      return null;
    });
    return _cachedAppVersion!;
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

  bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return null;
  }

  String? _normalizeOptionalString(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  List<String> _extractSearchKeywords(dynamic raw) {
    final List<String> keywords = [];
    final Set<String> seen = {};
    if (raw is List) {
      for (final entry in raw) {
        if (entry == null) continue;
        final normalized = entry.toString().trim().toLowerCase();
        if (normalized.isEmpty) continue;
        if (seen.add(normalized)) {
          keywords.add(normalized);
        }
      }
    }
    return keywords;
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
    const int zeroPenalty = -100; // penalize zero-value totals so non-zero always wins
    const List<String> excludedPhrases = [
      'tendered',
      'change',
      'balance due',
      'cash received',
      'amount tendered',
    ];
    final keywordWeights = {
      'total paid': 220,
      'total inc tax': 210,
      'grand total': 200,
      'amount payable': 190,
      'invoice total': 180,
      'amount due': 170,
      'total': 160,
      'subtotal': 120,
      'paid': 110,
      'eftpos': 100,
      'payment': 100,
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
      if (excludedPhrases.any((phrase) => lower.contains(phrase))) {
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
            final lowerAdj = la.toLowerCase();
            if (excludedPhrases.any((phrase) => lowerAdj.contains(phrase))) {
              continue;
            }
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
          final adjustedScore = bestWeight + (a == 0.0 ? zeroPenalty : 0);
          candidates.add(_Cand(value: a, score: adjustedScore, line: line));
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
        if (excludedPhrases.any((phrase) => lower.contains(phrase))) continue;
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
          if (v != null) {
            final adjustedScore = 75 + (v == 0.0 ? zeroPenalty : 0);
            candidates.add(_Cand(value: v, score: adjustedScore, line: line));
          }
        }
      }
    }

    if (candidates.isNotEmpty) {
      candidates.sort((b, a) {
        final sc = a.score.compareTo(b.score);
        if (sc != 0) return sc;
        return a.value.compareTo(b.value);
      });
      // Prefer the largest non-zero value; return 0 only if all are zero.
      double? bestNonZero;
      double? bestZero;
      for (final c in candidates) {
        if (c.value > 0) {
          if (bestNonZero == null || c.value > bestNonZero) {
            bestNonZero = c.value;
          }
        } else if (c.value == 0) {
          bestZero = 0.0;
        }
      }
      return bestNonZero ?? bestZero;
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
    final String? normalizedParsed =
        parsedCurrency != null && parsedCurrency.trim().isNotEmpty
            ? parsedCurrency.toUpperCase()
            : null;

    final lower = rawText.toLowerCase();

    // Explicit currency codes
    final codeRe = RegExp(
      r'\b(AUD|USD|GBP|EUR|CAD|NZD|SGD|INR|JPY|CNY)\b',
      caseSensitive: false,
    );
    final match = codeRe.firstMatch(rawText);
    if (match != null) return match.group(1)!.toUpperCase();

    final List<_CurrencyHint> hints = [
      _CurrencyHint(
        code: 'INR',
        regexes: [
          RegExp(r'₹'),
          RegExp(
            r'\b(inr|rs\.?|rs|rupees?|rup(?:ee|e|ies)?|pupees?)\b',
            caseSensitive: false,
          ),
        ],
        localeKeywords: [
          'india',
          'bharat',
          'hyderabad',
          'mumbai',
          'delhi',
          'bangalore',
          'chennai',
          'telangana',
          'gachibowli',
        ],
        phonePatterns: [
          RegExp(r'\+?91[\s-]?\d{6,}'),
        ],
      ),
      _CurrencyHint(
        code: 'AUD',
        regexes: [
          RegExp(r'\baud\b', caseSensitive: false),
          RegExp(r'australian dollars?', caseSensitive: false),
        ],
        localeKeywords: [
          'australia',
          '.au',
          'sydney',
          'melbourne',
          'brisbane',
          'abn',
        ],
        phonePatterns: [
          RegExp(r'\+?61[\s-]?\d{4,}'),
        ],
      ),
      _CurrencyHint(
        code: 'NZD',
        regexes: [
          RegExp(r'\bnzd\b', caseSensitive: false),
        ],
        localeKeywords: [
          'new zealand',
          '.nz',
          'auckland',
          'wellington',
        ],
      ),
      _CurrencyHint(
        code: 'CAD',
        regexes: [
          RegExp(r'\bcad\b', caseSensitive: false),
          RegExp(r'canadian dollars?', caseSensitive: false),
          RegExp(r'gst/?hst', caseSensitive: false),
        ],
        localeKeywords: [
          'canada',
          '.ca',
          'toronto',
          'vancouver',
          'montreal',
        ],
        phonePatterns: [
          RegExp(r'\+?1[\s-]?\d{3}[\s-]?\d{3}[\s-]?\d{4}'),
        ],
      ),
      _CurrencyHint(
        code: 'SGD',
        regexes: [
          RegExp(r'\bsgd\b', caseSensitive: false),
        ],
        localeKeywords: [
          'singapore',
          '.sg',
        ],
        phonePatterns: [
          RegExp(r'\+?65[\s-]?\d{4}[\s-]?\d{4}'),
        ],
      ),
      _CurrencyHint(
        code: 'GBP',
        regexes: [
          RegExp(r'£'),
          RegExp(r'\bgbp\b', caseSensitive: false),
          RegExp(r'\bpounds?\b', caseSensitive: false),
        ],
        localeKeywords: [
          'united kingdom',
          'uk',
          'england',
          'scotland',
          'wales',
          '.uk',
        ],
      ),
      _CurrencyHint(
        code: 'EUR',
        regexes: [
          RegExp(r'€'),
          RegExp(r'\beur\b', caseSensitive: false),
          RegExp(r'\beuros?\b', caseSensitive: false),
        ],
        localeKeywords: [
          'europe',
          'germany',
          'france',
          'spain',
          'italy',
          'netherlands',
        ],
      ),
      _CurrencyHint(
        code: 'USD',
        regexes: [
          RegExp(r'\busd\b', caseSensitive: false),
          RegExp(r'us dollars?', caseSensitive: false),
        ],
        localeKeywords: [
          'united states',
          'usa',
          'united states of america',
          '.us',
          'new york',
          'california',
        ],
        phonePatterns: [
          RegExp(r'\+?1[\s-]?\d{3}[\s-]?\d{3}[\s-]?\d{4}'),
        ],
      ),
      _CurrencyHint(
        code: 'JPY',
        regexes: [
          RegExp(r'¥'),
          RegExp(r'\byen\b', caseSensitive: false),
          RegExp(r'\bjpy\b', caseSensitive: false),
        ],
        localeKeywords: [
          'japan',
          '.jp',
          'tokyo',
          'osaka',
        ],
      ),
      _CurrencyHint(
        code: 'CNY',
        regexes: [
          RegExp(r'\bcny\b', caseSensitive: false),
          RegExp(r'\byuan\b', caseSensitive: false),
          RegExp(r'\brenminbi\b', caseSensitive: false),
          RegExp(r'\brmb\b', caseSensitive: false),
        ],
        localeKeywords: [
          'china',
          '.cn',
          'beijing',
          'shanghai',
          'guangzhou',
        ],
      ),
    ];

    for (final hint in hints) {
      if (hint.matches(rawText, lower)) {
        return hint.code;
      }
    }

    // No heuristic hit; use GPT-provided value if present.
    if (normalizedParsed != null) {
      return normalizedParsed;
    }

    // Fallback: USD (if we cannot infer or GPT gave nothing meaningful)
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

class _CurrencyHint {
  const _CurrencyHint({
    required this.code,
    this.regexes = const [],
    this.localeKeywords = const [],
    this.phonePatterns = const [],
  });

  final String code;
  final List<RegExp> regexes;
  final List<String> localeKeywords;
  final List<RegExp> phonePatterns;

  bool matches(String rawText, String lowerText) {
    if (regexes.any((regex) => regex.hasMatch(rawText))) {
      return true;
    }

    if (localeKeywords.any((keyword) => lowerText.contains(keyword))) {
      return true;
    }

    if (phonePatterns.any((pattern) => pattern.hasMatch(rawText))) {
      return true;
    }

    return false;
  }
}
