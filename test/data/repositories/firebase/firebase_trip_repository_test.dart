import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_trip_repository.dart';
import 'package:receiptnest/domain/entities/trip.dart';

void main() {
  const userId = 'user-1';

  group('FirebaseTripRepository', () {
    test('createTrip and getTrip round-trip the trip model', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseTripRepository(firestore: firestore);
      final trip = Trip(
        id: 'trip-1',
        name: 'Work Travel',
        type: TripType.work,
        status: TripStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      await repository.createTrip(userId, trip);
      final result = await repository.getTrip(userId, 'trip-1');

      expect(result, isNotNull);
      expect(result!.id, 'trip-1');
      expect(result.name, 'Work Travel');
      expect(result.type, TripType.work);
      expect(result.status, TripStatus.active);
    });

    test('watchTrips maps firestore docs into Trip models', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseTripRepository(firestore: firestore);

      final future = repository.watchTrips(userId).firstWhere(
        (trips) => trips.isNotEmpty,
      );

      await firestore.collection('users').doc(userId).collection('trips').add(
        <String, Object?>{
          'name': 'Personal Trip',
          'type': 'personal',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 2)),
        },
      );

      final trips = await future.timeout(const Duration(seconds: 2));

      expect(trips, hasLength(1));
      expect(trips.single.name, 'Personal Trip');
      expect(trips.single.type, TripType.personal);
      expect(trips.single.status, TripStatus.completed);
    });

    test('deleteTrip unlinks receipts before deleting the trip', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseTripRepository(firestore: firestore);

      await firestore.collection('users').doc(userId).collection('trips').doc(
        'trip-1',
      ).set(<String, Object?>{
        'name': 'Trip',
        'type': 'work',
        'status': 'active',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      await firestore
          .collection('users')
          .doc(userId)
          .collection('receipts')
          .doc('receipt-1')
          .set(<String, Object?>{
        'storeName': 'Cafe',
        'date': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'total': 10.0,
        'currency': 'AUD',
        'tripId': 'trip-1',
      });

      await repository.deleteTrip(userId, 'trip-1');

      final tripDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('trips')
          .doc('trip-1')
          .get();
      final receiptDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('receipts')
          .doc('receipt-1')
          .get();

      expect(tripDoc.exists, isFalse);
      expect(receiptDoc.data()!['tripId'], isNull);
    });
  });
}
