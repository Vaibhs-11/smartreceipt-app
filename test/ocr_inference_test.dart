import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/domain/entities/ocr_result.dart';

void main() {
  test('Infers quantity and unit price from "2 x 1.99" when total matches', () {
    final result = OcrResult(
      storeName: 'Store',
      date: DateTime(2025, 1, 1),
      total: 3.98,
      rawText: '2 x 1.99',
      items: const [
        OcrReceiptItem(name: 'ITEM 2 x 1.99', price: 3.98),
      ],
    );

    final items = result.toReceiptItems();
    expect(items, hasLength(1));
    final item = items.first;

    expect(item.price, 3.98);
    expect(item.quantity, 2);
    expect(item.unitPrice, 1.99);
  });

  test('Does not infer from qty-only patterns like "QTY 2"', () {
    final result = OcrResult(
      storeName: 'Store',
      date: DateTime(2025, 1, 1),
      total: 3.98,
      rawText: 'QTY 2',
      items: const [
        OcrReceiptItem(name: 'ITEM QTY 2', price: 3.98),
      ],
    );

    final items = result.toReceiptItems();
    expect(items, hasLength(1));
    final item = items.first;

    expect(item.price, 3.98);
    expect(item.quantity, isNull);
    expect(item.unitPrice, isNull);
  });

  test('Discards inference when line total does not match', () {
    final result = OcrResult(
      storeName: 'Store',
      date: DateTime(2025, 1, 1),
      total: 4.50,
      rawText: '2 x 1.99',
      items: const [
        OcrReceiptItem(name: 'ITEM 2 x 1.99', price: 4.50),
      ],
    );

    final items = result.toReceiptItems();
    expect(items, hasLength(1));
    final item = items.first;

    expect(item.price, 4.50);
    expect(item.quantity, isNull);
    expect(item.unitPrice, isNull);
  });
}
