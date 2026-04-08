import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/domain/entities/trip.dart';

void main() {
  group('TripTypeX.fromString', () {
    test('defaults to personal for null or unknown values', () {
      expect(TripTypeX.fromString(null), TripType.personal);
      expect(TripTypeX.fromString('unknown'), TripType.personal);
    });

    test('maps work correctly', () {
      expect(TripTypeX.fromString('work'), TripType.work);
    });
  });

  group('TripStatusX.fromString', () {
    test('defaults to active for null or unknown values', () {
      expect(TripStatusX.fromString(null), TripStatus.active);
      expect(TripStatusX.fromString('unknown'), TripStatus.active);
    });

    test('maps completed correctly', () {
      expect(TripStatusX.fromString('completed'), TripStatus.completed);
    });
  });

  group('Trip.fromMap', () {
    test('parses a full firestore-style map', () {
      final createdAt = Timestamp.fromDate(DateTime.utc(2026, 1, 10));
      final updatedAt = Timestamp.fromDate(DateTime.utc(2026, 1, 11));
      final startDate = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
      final endDate = Timestamp.fromDate(DateTime.utc(2026, 1, 5));
      final lastExportedAt = Timestamp.fromDate(DateTime.utc(2026, 1, 12));

      final trip = Trip.fromMap(
        <String, Object?>{
          'id': 'trip-1',
          'name': 'Melbourne Work Trip',
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

      expect(trip.id, 'trip-1');
      expect(trip.name, 'Melbourne Work Trip');
      expect(trip.type, TripType.work);
      expect(trip.startDate!.toUtc(), DateTime.utc(2026, 1, 1));
      expect(trip.endDate!.toUtc(), DateTime.utc(2026, 1, 5));
      expect(trip.notes, 'Keep invoices');
      expect(trip.status, TripStatus.completed);
      expect(trip.createdAt.toUtc(), DateTime.utc(2026, 1, 10));
      expect(trip.updatedAt.toUtc(), DateTime.utc(2026, 1, 11));
      expect(trip.totalAmount, 123.45);
      expect(trip.receiptCount, 4);
      expect(trip.lastExportedAt!.toUtc(), DateTime.utc(2026, 1, 12));
    });

    test('defaults optional and required values safely when fields are missing', () {
      final before = DateTime.now();
      final trip = Trip.fromMap(const <String, Object?>{});
      final after = DateTime.now();

      expect(trip.id, '');
      expect(trip.name, '');
      expect(trip.type, TripType.personal);
      expect(trip.status, TripStatus.active);
      expect(trip.startDate, isNull);
      expect(trip.endDate, isNull);
      expect(trip.notes, isNull);
      expect(trip.totalAmount, isNull);
      expect(trip.receiptCount, isNull);
      expect(trip.lastExportedAt, isNull);
      expect(
        trip.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        trip.updatedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('accepts mixed date formats', () {
      final trip = Trip.fromMap(
        <String, Object?>{
          'id': 'trip-2',
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

      expect(trip.type, TripType.personal);
      expect(trip.status, TripStatus.active);
      expect(trip.startDate!.toUtc(), DateTime.utc(2026, 2, 1));
      expect(
        trip.endDate!.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1760054400000, isUtc: true),
      );
      expect(trip.createdAt.toUtc(), DateTime.utc(2026, 2, 2));
      expect(trip.updatedAt.toUtc(), DateTime.utc(2026, 2, 3));
      expect(
        trip.lastExportedAt!.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1760140800000, isUtc: true),
      );
    });
  });
}
