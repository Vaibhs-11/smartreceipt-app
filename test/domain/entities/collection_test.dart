import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/domain/entities/collection.dart';

void main() {
  group('CollectionTypeX.fromString', () {
    test('defaults to personal for null or unknown values', () {
      expect(CollectionTypeX.fromString(null), CollectionType.personal);
      expect(
        CollectionTypeX.fromString('unknown'),
        CollectionType.personal,
      );
    });

    test('maps work correctly', () {
      expect(CollectionTypeX.fromString('work'), CollectionType.work);
    });
  });

  group('CollectionStatusX.fromString', () {
    test('defaults to active for null or unknown values', () {
      expect(CollectionStatusX.fromString(null), CollectionStatus.active);
      expect(
        CollectionStatusX.fromString('unknown'),
        CollectionStatus.active,
      );
    });

    test('maps completed correctly', () {
      expect(
        CollectionStatusX.fromString('completed'),
        CollectionStatus.completed,
      );
    });
  });

  group('Collection.fromMap', () {
    test('parses a full firestore-style map', () {
      final createdAt = Timestamp.fromDate(DateTime.utc(2026, 1, 10));
      final updatedAt = Timestamp.fromDate(DateTime.utc(2026, 1, 11));
      final startDate = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
      final endDate = Timestamp.fromDate(DateTime.utc(2026, 1, 5));
      final lastExportedAt = Timestamp.fromDate(DateTime.utc(2026, 1, 12));

      final collection = Collection.fromMap(
        <String, Object?>{
          'id': 'collection-1',
          'name': 'Melbourne Work Event',
          'type': 'work',
          'startDate': startDate,
          'endDate': endDate,
          'notes': 'Keep invoices',
          'status': 'completed',
          'createdAt': createdAt,
          'updatedAt': updatedAt,
          'totalAmount': 123.45,
          'receiptCount': 4,
          'lastExportedAt': lastExportedAt,
        },
      );

      expect(collection.id, 'collection-1');
      expect(collection.name, 'Melbourne Work Event');
      expect(collection.type, CollectionType.work);
      expect(collection.startDate!.toUtc(), DateTime.utc(2026, 1, 1));
      expect(collection.endDate!.toUtc(), DateTime.utc(2026, 1, 5));
      expect(collection.notes, 'Keep invoices');
      expect(collection.status, CollectionStatus.completed);
      expect(collection.createdAt.toUtc(), DateTime.utc(2026, 1, 10));
      expect(collection.updatedAt.toUtc(), DateTime.utc(2026, 1, 11));
      expect(collection.totalAmount, 123.45);
      expect(collection.receiptCount, 4);
      expect(collection.lastExportedAt!.toUtc(), DateTime.utc(2026, 1, 12));
    });

    test('defaults optional and required values safely when fields are missing',
        () {
      final before = DateTime.now();
      final collection = Collection.fromMap(const <String, Object?>{});
      final after = DateTime.now();

      expect(collection.id, '');
      expect(collection.name, '');
      expect(collection.type, CollectionType.personal);
      expect(collection.status, CollectionStatus.active);
      expect(collection.startDate, isNull);
      expect(collection.endDate, isNull);
      expect(collection.notes, isNull);
      expect(collection.totalAmount, isNull);
      expect(collection.receiptCount, isNull);
      expect(collection.lastExportedAt, isNull);
      expect(
        collection.createdAt
            .isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        collection.updatedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('accepts mixed date formats', () {
      final collection = Collection.fromMap(
        <String, Object?>{
          'id': 'collection-2',
          'name': 'Mixed Formats',
          'type': 'unexpected',
          'status': 'unexpected',
          'startDate': '2026-02-01T00:00:00.000Z',
          'endDate': 1760054400000,
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 2, 2)),
          'updatedAt': '2026-02-03T00:00:00.000Z',
          'lastExportedAt': 1760140800000.0,
        },
      );

      expect(collection.type, CollectionType.personal);
      expect(collection.status, CollectionStatus.active);
      expect(collection.startDate!.toUtc(), DateTime.utc(2026, 2, 1));
      expect(
        collection.endDate!.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1760054400000, isUtc: true),
      );
      expect(collection.createdAt.toUtc(), DateTime.utc(2026, 2, 2));
      expect(collection.updatedAt.toUtc(), DateTime.utc(2026, 2, 3));
      expect(
        collection.lastExportedAt!.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1760140800000, isUtc: true),
      );
    });
  });
}
