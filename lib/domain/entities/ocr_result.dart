import 'package:equatable/equatable.dart';
import 'package:receiptnest/domain/entities/receipt.dart' show ReceiptItem;

class OcrReceiptItem extends Equatable {
  final String name;
  final double? price;
  final String priceConfidence; // "high" or "low"

  const OcrReceiptItem({
    required this.name,
    required this.price,
    this.priceConfidence = "high",
  });

  @override
  List<Object?> get props => [name, price, priceConfidence];
}

class OcrResult extends Equatable {
  final bool isReceipt;
  final String? receiptRejectionReason;
  final String storeName;
  final DateTime date;
  final double total;
  final String rawText;
  final List<OcrReceiptItem> items;
  final String? currency;
  final List<String> searchKeywords;
  final String? normalizedBrand;
  final String? category;

  const OcrResult({
    this.isReceipt = true,
    this.receiptRejectionReason,
    required this.storeName,
    required this.date,
    required this.total,
    required this.rawText,
    this.items = const [],
    this.currency,
    this.searchKeywords = const [],
    this.normalizedBrand,
    this.category,
  });

  /// ✅ Helper: convert OCR items into domain ReceiptItems
  List<ReceiptItem> toReceiptItems() {
  print("----- OCR RESULT DEBUG START -----");
  print("Total OCR items received: ${items.length}");

  final mapped = items.map((ocrItem) {
    final lineTotal = ocrItem.price;

    print(
      "OCR ITEM → name: '${ocrItem.name}' | "
      "price: ${ocrItem.price} | "
      "confidence: ${ocrItem.priceConfidence}",
    );

    final inference = lineTotal != null && lineTotal > 0
        ? _inferQuantityAndUnitPrice(ocrItem.name, lineTotal)
        : null;

    if (inference != null) {
      print(
        "  ↳ Inferred quantity: ${inference.quantity}, "
        "unitPrice: ${inference.unitPrice}",
      );
    }

    final receiptItem = ReceiptItem(
      name: ocrItem.name,
      price: lineTotal,
      quantity: inference?.quantity,
      unitPrice: inference?.unitPrice,
    );

    print(
      "MAPPED ITEM → name: '${receiptItem.name}' | "
      "price: ${receiptItem.price}",
    );

    return receiptItem;
  }).toList();

  for (final item in mapped) {
    print("FINAL LIST ITEM → '${item.name}' | price: ${item.price}");
  }

  print("----- OCR RESULT DEBUG END -----");

  return mapped;
}

  @override
  List<Object?> get props => [
        storeName,
        date,
        total,
        rawText,
        items,
        isReceipt,
        receiptRejectionReason,
        currency,
        searchKeywords,
        normalizedBrand,
        category,
      ];
}

class _QuantityInference {
  final double quantity;
  final double unitPrice;

  const _QuantityInference({
    required this.quantity,
    required this.unitPrice,
  });
}

_QuantityInference? _inferQuantityAndUnitPrice(
  String name,
  double lineTotal,
) {
  if (lineTotal <= 0) return null;

  final text = name.toLowerCase();

  final qtyUnitMatch = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:x|\u00d7|@|\*)\s*(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  ).firstMatch(text);

  if (qtyUnitMatch != null) {
    final first = _parseNumber(qtyUnitMatch.group(1));
    final second = _parseNumber(qtyUnitMatch.group(2));
    if (first != null && second != null) {
      final candidate = _selectBestQuantityPair(
        first,
        second,
        lineTotal,
      );
      if (candidate != null) {
        return candidate;
      }
    }
  }

  final qtyOnlyMatch = RegExp(
    r'\b(?:qty|quantity)\s*[:x=]?\s*(\d+(?:[.,]\d+)?)\b',
    caseSensitive: false,
  ).firstMatch(text);

  if (qtyOnlyMatch != null) {
    // Qty-only patterns are not enough to infer unit price or quantity reliably.
    return null;
  }

  return null;
}

_QuantityInference? _selectBestQuantityPair(
  double a,
  double b,
  double lineTotal,
) {
  final aAsQuantity = _isReasonableQuantity(a);
  final bAsQuantity = _isReasonableQuantity(b);

  final candidates = <_QuantityInference>[];

  if (aAsQuantity && _matchesLineTotal(a, b, lineTotal)) {
    candidates.add(_QuantityInference(quantity: a, unitPrice: b));
  }
  if (bAsQuantity && _matchesLineTotal(b, a, lineTotal)) {
    candidates.add(_QuantityInference(quantity: b, unitPrice: a));
  }

  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first;

  // Prefer integer-like quantities when both options match.
  candidates.sort((left, right) {
    final leftScore = _integerScore(left.quantity);
    final rightScore = _integerScore(right.quantity);
    return rightScore.compareTo(leftScore);
  });
  return candidates.first;
}

bool _matchesLineTotal(double quantity, double unitPrice, double lineTotal) {
  if (quantity <= 0 || unitPrice <= 0) return false;
  final expected = quantity * unitPrice;
  final diff = (expected - lineTotal).abs();
  return diff <= 0.02;
}

bool _isReasonableQuantity(double value) {
  if (value <= 0) return false;
  if (value > 1000) return false;
  return true;
}

int _integerScore(double value) {
  return (value - value.round()).abs() < 0.001 ? 1 : 0;
}

double? _parseNumber(String? raw) {
  if (raw == null) return null;
  var cleaned = raw.replaceAll(RegExp(r'[^0-9,\.]'), '');
  if (cleaned.isEmpty) return null;
  if (cleaned.contains(',') && cleaned.contains('.')) {
    if (cleaned.lastIndexOf('.') > cleaned.lastIndexOf(',')) {
      cleaned = cleaned.replaceAll(',', '');
    } else {
      cleaned = cleaned.replaceAll('.', '');
      cleaned = cleaned.replaceAll(',', '.');
    }
  } else {
    cleaned = cleaned.replaceAll(',', '.');
  }
  return double.tryParse(cleaned);
}
