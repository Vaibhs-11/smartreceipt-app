import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/models/categorised_item_view.dart';
import 'package:receiptnest/presentation/models/grouped_item_results.dart';

void main() {
  group('groupItemResults', () {
    test('groups matching items by month and receipt', () {
      final newerReceipt = _receipt(
        id: 'newer',
        store: 'Officeworks',
        date: DateTime(2026, 3, 15),
      );
      final olderReceipt = _receipt(
        id: 'older',
        store: 'MYER',
        date: DateTime(2026, 2, 10),
      );

      final groups = groupItemResults(
        receipts: [olderReceipt, newerReceipt],
        items: [
          _item(
            receipt: olderReceipt,
            itemIndex: 0,
            name: 'Lego',
            price: 20,
          ),
          _item(
            receipt: newerReceipt,
            itemIndex: 1,
            name: 'Paper',
            price: 10,
          ),
          _item(
            receipt: newerReceipt,
            itemIndex: 0,
            name: 'Folder',
            price: 5,
          ),
        ],
      );

      expect(
        groups.map((group) => group.monthKey),
        [DateTime(2026, 3), DateTime(2026, 2)],
      );
      expect(groups.first.receipts.single.receipt.id, 'newer');
      expect(
        groups.first.receipts.single.items.map((item) => item.itemName),
        ['Folder', 'Paper'],
      );
      expect(groups.first.receipts.single.displayedSubtotal, 15);
    });

    test('keeps receipts with the same merchant and date separate', () {
      final first = _receipt(
        id: 'first',
        store: 'Coles',
        date: DateTime(2026, 3, 1),
      );
      final second = _receipt(
        id: 'second',
        store: 'Coles',
        date: DateTime(2026, 3, 1),
      );

      final groups = groupItemResults(
        receipts: [first, second],
        items: [
          _item(receipt: first, itemIndex: 0, name: 'Milk', price: 4),
          _item(receipt: second, itemIndex: 0, name: 'Bread', price: 3),
        ],
      );

      expect(groups.single.receipts, hasLength(2));
      expect(
        groups.single.receipts.map((group) => group.receipt.id).toSet(),
        {'first', 'second'},
      );
    });

    test('keeps included receipts that do not have item rows', () {
      final receipt = _receipt(
        id: 'manual',
        store: 'Manual receipt',
        date: DateTime(2026, 1, 20),
        total: 42,
      );

      final groups = groupItemResults(
        receipts: [receipt],
        items: const [],
        includedReceiptIds: {'manual'},
      );

      final receiptGroup = groups.single.receipts.single;
      expect(receiptGroup.items, isEmpty);
      expect(receiptGroup.displayedSubtotal, 42);
    });

    test('keeps only supplied item matches within a receipt', () {
      final receipt = _receipt(
        id: 'receipt',
        store: 'The Body Shop',
        date: DateTime(2026, 2, 28),
      );

      final groups = groupItemResults(
        receipts: [receipt],
        items: [
          _item(
            receipt: receipt,
            itemIndex: 1,
            name: 'British Rose Hand Cream',
            price: 10,
          ),
        ],
      );

      expect(
        groups.single.receipts.single.items.single.itemName,
        'British Rose Hand Cream',
      );
      expect(groups.single.receipts.single.displayedSubtotal, 10);
    });

    test('keeps every supplied item for an included receipt', () {
      final receipt = _receipt(
        id: 'store-match',
        store: 'Officeworks',
        date: DateTime(2026, 3, 15),
      );

      final groups = groupItemResults(
        receipts: [receipt],
        items: [
          _item(
            receipt: receipt,
            itemIndex: 0,
            name: 'Folder',
            price: 5,
          ),
          _item(
            receipt: receipt,
            itemIndex: 1,
            name: 'Paper',
            price: 10,
          ),
        ],
        includedReceiptIds: {'store-match'},
      );

      expect(
        groups.single.receipts.single.items.map((item) => item.itemName),
        ['Folder', 'Paper'],
      );
      expect(groups.single.receipts.single.displayedSubtotal, 15);
    });

    test('ignores items and requested ids without a matching receipt', () {
      final receipt = _receipt(
        id: 'known',
        store: 'Known',
        date: DateTime(2026, 1, 1),
      );
      final missingReceiptItem = CategorisedItemView(
        receiptId: 'missing',
        itemIndex: 0,
        itemName: 'Unknown',
        price: 10,
        merchant: 'Unknown',
        date: DateTime(2026, 1, 1),
        category: null,
        taxClaimable: false,
      );

      final groups = groupItemResults(
        receipts: [receipt],
        items: [missingReceiptItem],
        includedReceiptIds: {'missing'},
      );

      expect(groups, isEmpty);
    });
  });
}

Receipt _receipt({
  required String id,
  required String store,
  required DateTime date,
  double total = 100,
}) {
  return Receipt(
    id: id,
    storeName: store,
    date: date,
    total: total,
    currency: 'AUD',
  );
}

CategorisedItemView _item({
  required Receipt receipt,
  required int itemIndex,
  required String name,
  required double price,
}) {
  return CategorisedItemView(
    receiptId: receipt.id,
    itemIndex: itemIndex,
    itemName: name,
    price: price,
    merchant: receipt.storeName,
    date: receipt.date,
    category: null,
    taxClaimable: false,
  );
}
