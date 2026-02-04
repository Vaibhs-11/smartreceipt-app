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
    final filtered = items
        .where((item) => item.price != null && item.price! > 0)
        .toList();

    return filtered
        .map((ocrItem) =>
            ReceiptItem(name: ocrItem.name, price: ocrItem.price ?? 0.0))
        .toList();
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
