import 'package:equatable/equatable.dart';
import 'package:smartreceipt/domain/entities/receipt.dart' show ReceiptItem;

class OcrReceiptItem extends Equatable {
  final String name;
  final double price;

  const OcrReceiptItem({required this.name, required this.price});

  @override
  List<Object?> get props => [name, price];
}

class OcrResult extends Equatable {
  final String storeName;
  final DateTime date;
  final double total;
  final String rawText;
  final List<OcrReceiptItem> items;

  const OcrResult({
    required this.storeName,
    required this.date,
    required this.total,
    required this.rawText,
    this.items = const [],
  });

  /// ✅ Helper: convert OCR items into domain ReceiptItems
  List<ReceiptItem> toReceiptItems() {
    return items
        .map((ocrItem) =>
            ReceiptItem(name: ocrItem.name, price: ocrItem.price))
        .toList();
  }

  @override
  List<Object?> get props => [storeName, date, total, rawText, items];
}
