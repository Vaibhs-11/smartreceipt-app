import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/models/insights_query.dart';
import 'package:receiptnest/domain/services/insights_engine.dart';

void main() {
  group('InsightsEngine', () {
    const engine = InsightsEngine();

    test('single-currency category aggregation', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            currency: 'AUD',
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Coffee', price: 5, category: 'Food'),
              ReceiptItem(name: 'Train', price: 15, category: 'Travel'),
            ],
          ),
          _receipt(
            id: 'r2',
            currency: 'AUD',
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Lunch', price: 20, category: 'Food'),
            ],
          ),
        ],
        query: const InsightsQuery(),
      );

      expect(result.receiptCount, 2);
      expect(result.itemCount, 3);
      expect(result.currencies, hasLength(1));
      expect(result.currencies.first.currency, 'AUD');
      expect(result.currencies.first.totalAmount, 40);

      final food = result.currencies.first.categories.firstWhere(
        (category) => category.category == 'Food',
      );
      final travel = result.currencies.first.categories.firstWhere(
        (category) => category.category == 'Travel',
      );

      expect(food.totalAmount, 25);
      expect(food.percentage, closeTo(0.625, 0.0001));
      expect(food.receiptCount, 2);
      expect(travel.totalAmount, 15);
      expect(travel.percentage, closeTo(0.375, 0.0001));
    });

    test('multi-currency separation', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            currency: 'AUD',
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Coffee', price: 5, category: 'Food'),
            ],
          ),
          _receipt(
            id: 'r2',
            currency: 'USD',
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Taxi', price: 10, category: 'Transport'),
            ],
          ),
        ],
        query: const InsightsQuery(),
      );

      expect(result.currencies, hasLength(2));

      final aud = result.currencies.firstWhere(
        (currency) => currency.currency == 'AUD',
      );
      final usd = result.currencies.firstWhere(
        (currency) => currency.currency == 'USD',
      );

      expect(aud.totalAmount, 5);
      expect(aud.categories.single.category, 'Food');
      expect(usd.totalAmount, 10);
      expect(usd.categories.single.category, 'Transport');
    });

    test('collection query uses collection category', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            collectionId: 'trip-1',
            items: const <ReceiptItem>[
              ReceiptItem(
                name: 'Coffee',
                price: 5,
                category: 'Office',
                collectionCategory: 'Food & Drinks',
              ),
            ],
          ),
        ],
        query: const InsightsQuery(collectionId: 'trip-1'),
      );

      expect(
          result.currencies.single.categories.single.category, 'Food & Drinks');
    });

    test('collection query prefers manual collection category override', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            collectionId: 'trip-1',
            items: const <ReceiptItem>[
              ReceiptItem(
                name: 'Coffee',
                price: 5,
                category: 'Office',
                collectionCategory: 'Food & Drinks',
                manualCollectionCategory: 'Travel',
              ),
            ],
          ),
        ],
        query: const InsightsQuery(collectionId: 'trip-1'),
      );

      expect(result.currencies.single.categories.single.category, 'Travel');
    });

    test('non-collection query uses normal category', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            collectionId: 'trip-1',
            items: const <ReceiptItem>[
              ReceiptItem(
                name: 'Coffee',
                price: 5,
                category: 'Office',
                collectionCategory: 'Food & Drinks',
              ),
            ],
          ),
        ],
        query: const InsightsQuery(),
      );

      expect(result.currencies.single.categories.single.category, 'Office');
    });

    test('taxOnly filters correctly', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            items: const <ReceiptItem>[
              ReceiptItem(
                name: 'Laptop Bag',
                price: 50,
                category: 'Shopping',
                taxClaimable: true,
              ),
              ReceiptItem(
                name: 'Snack',
                price: 5,
                category: 'Food',
              ),
            ],
          ),
        ],
        query: const InsightsQuery(taxOnly: true),
      );

      expect(result.receiptCount, 1);
      expect(result.itemCount, 1);
      expect(result.currencies.single.totalAmount, 50);
      expect(result.currencies.single.categories.single.category, 'Shopping');
    });

    test('date range filters correctly', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            date: DateTime.utc(2026, 1, 5),
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Coffee', price: 5, category: 'Food'),
            ],
          ),
          _receipt(
            id: 'r2',
            date: DateTime.utc(2026, 1, 20),
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Taxi', price: 10, category: 'Transport'),
            ],
          ),
        ],
        query: InsightsQuery(
          startDate: DateTime.utc(2026, 1, 10),
          endDate: DateTime.utc(2026, 1, 31),
        ),
      );

      expect(result.receiptCount, 1);
      expect(result.itemCount, 1);
      expect(result.startDate, DateTime.utc(2026, 1, 20));
      expect(result.endDate, DateTime.utc(2026, 1, 20));
      expect(result.currencies.single.categories.single.category, 'Transport');
    });

    test('null or blank category falls back to Misc', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Mystery', price: 7, category: null),
              ReceiptItem(name: 'Blank', price: 3, category: '   '),
            ],
          ),
        ],
        query: const InsightsQuery(),
      );

      expect(result.currencies.single.categories.single.category, 'Misc');
      expect(result.currencies.single.categories.single.totalAmount, 10);
    });

    test('empty receipts or empty items does not crash', () {
      final emptyReceiptsResult = engine.build(
        receipts: const <Receipt>[],
        query: const InsightsQuery(),
      );
      final emptyItemsResult = engine.build(
        receipts: <Receipt>[
          _receipt(id: 'r1', items: const <ReceiptItem>[]),
        ],
        query: const InsightsQuery(),
      );

      expect(emptyReceiptsResult.isEmpty, isTrue);
      expect(emptyItemsResult.isEmpty, isTrue);
    });

    test('receipt contributions are generated correctly', () {
      final result = engine.build(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            storeName: 'Cafe Blue',
            date: DateTime.utc(2026, 2, 1),
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Coffee', price: 5, category: 'Food'),
              ReceiptItem(name: 'Cake', price: 7, category: 'Food'),
            ],
          ),
          _receipt(
            id: 'r2',
            storeName: '',
            date: DateTime.utc(2026, 2, 2),
            items: const <ReceiptItem>[
              ReceiptItem(name: 'Lunch', price: 9, category: 'Food'),
            ],
          ),
        ],
        query: const InsightsQuery(),
      );

      final food = result.currencies.single.categories.singleWhere(
        (category) => category.category == 'Food',
      );

      expect(food.receiptContributions, hasLength(2));
      expect(food.receiptContributions.first.receiptId, 'r1');
      expect(food.receiptContributions.first.merchant, 'Cafe Blue');
      expect(food.receiptContributions.first.amount, 12);
      expect(food.receiptContributions[1].receiptId, 'r2');
      expect(food.receiptContributions[1].merchant, 'Unknown');
      expect(food.receiptContributions[1].amount, 9);
    });
  });
}

Receipt _receipt({
  required String id,
  String storeName = 'Store',
  DateTime? date,
  String currency = 'AUD',
  String? collectionId,
  List<ReceiptItem> items = const <ReceiptItem>[],
}) {
  return Receipt(
    id: id,
    storeName: storeName,
    date: date ?? DateTime.utc(2026, 1, 1),
    total: 0,
    currency: currency,
    collectionId: collectionId,
    items: items,
  );
}
