import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/domain/exceptions/trip_exception.dart';
import 'package:receiptnest/domain/repositories/trip_repository.dart';

class FirebaseTripRepository implements TripRepository {
  static const int _deleteBatchSize = 400;

  FirebaseTripRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _tripsCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('trips');
  }

  CollectionReference<Map<String, dynamic>> _receiptsCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('receipts');
  }

  @override
  Future<void> createTrip(String userId, Trip trip) async {
    final normalizedName = trip.name.trim().toLowerCase();
    final activeTripsSnapshot = await _tripsCollection(userId)
        .where('status', isEqualTo: TripStatus.active.asString)
        .get();
    final hasDuplicateActiveTrip = activeTripsSnapshot.docs
        .map(Trip.fromFirestore)
        .any(
          (existingTrip) =>
              existingTrip.name.trim().toLowerCase() == normalizedName,
        );

    if (hasDuplicateActiveTrip) {
      throw const DuplicateActiveTripException();
    }

    return _tripsCollection(userId).doc(trip.id).set(trip.toMap());
  }

  @override
  Future<void> updateTrip(String userId, Trip trip) {
    return _tripsCollection(userId).doc(trip.id).set(
          trip.toMap(),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> deleteTrip(String userId, String tripId) async {
    while (true) {
      final receiptBatch = await _receiptsCollection(userId)
          .where('tripId', isEqualTo: tripId)
          .limit(_deleteBatchSize)
          .get();

      if (receiptBatch.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();
      for (final receiptDoc in receiptBatch.docs) {
        batch.update(receiptDoc.reference, <String, Object?>{
          'tripId': null,
        });
      }
      await batch.commit();
    }

    await _tripsCollection(userId).doc(tripId).delete();
  }

  @override
  Future<Trip?> getTrip(String userId, String tripId) async {
    final snapshot = await _tripsCollection(userId).doc(tripId).get();
    if (!snapshot.exists) {
      return null;
    }
    return Trip.fromFirestore(snapshot);
  }

  @override
  Stream<Trip?> watchTrip(String userId, String tripId) {
    return _tripsCollection(userId).doc(tripId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return Trip.fromFirestore(snapshot);
    });
  }

  @override
  Stream<List<Trip>> watchTrips(String userId) {
    return _tripsCollection(userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(Trip.fromFirestore).toList();
    });
  }

  @override
  Future<List<Trip>> getTrips(String userId) async {
    final snapshot = await _tripsCollection(userId)
        .orderBy('updatedAt', descending: true)
        .get();
    return snapshot.docs.map(Trip.fromFirestore).toList();
  }

  @override
  Stream<List<Receipt>> watchReceiptsForTrip(String userId, String tripId) {
    return _receiptsCollection(userId)
        .where('tripId', isEqualTo: tripId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(Receipt.fromFirestore).toList();
    });
  }

  @override
  Future<List<Receipt>> getReceiptsForTrip(String userId, String tripId) async {
    final snapshot = await _receiptsCollection(userId)
        .where('tripId', isEqualTo: tripId)
        .get();
    return snapshot.docs.map(Receipt.fromFirestore).toList();
  }
}
