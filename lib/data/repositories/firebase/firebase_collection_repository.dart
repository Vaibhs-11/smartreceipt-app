import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/exceptions/collection_exception.dart';
import 'package:receiptnest/domain/repositories/collection_repository.dart';

class FirebaseCollectionRepository implements CollectionRepository {
  static const int _deleteBatchSize = 400;

  FirebaseCollectionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _tripsCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('trips');
  }

  CollectionReference<Map<String, dynamic>> _receiptsCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('receipts');
  }

  @override
  Future<void> createCollection(String userId, Collection collection) async {
    final normalizedName = collection.name.trim().toLowerCase();
    final activeTripsSnapshot = await _tripsCollection(userId)
        .where('status', isEqualTo: CollectionStatus.active.asString)
        .get();
    final hasDuplicateActiveTrip = activeTripsSnapshot.docs
        .map(Collection.fromFirestore)
        .any(
          (existingCollection) =>
              existingCollection.name.trim().toLowerCase() == normalizedName,
        );

    if (hasDuplicateActiveTrip) {
      throw const DuplicateActiveCollectionException();
    }

    return _tripsCollection(userId).doc(collection.id).set(collection.toMap());
  }

  @override
  Future<void> updateCollection(String userId, Collection collection) {
    return _tripsCollection(userId).doc(collection.id).set(
          collection.toMap(),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> deleteCollection(String userId, String collectionId) async {
    while (true) {
      final receiptBatch = await _receiptsCollection(userId)
          .where('collectionId', isEqualTo: collectionId)
          .limit(_deleteBatchSize)
          .get();

      if (receiptBatch.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();
      for (final receiptDoc in receiptBatch.docs) {
        batch.update(receiptDoc.reference, <String, Object?>{
          'collectionId': null,
        });
      }
      await batch.commit();
    }

    await _tripsCollection(userId).doc(collectionId).delete();
  }

  @override
  Future<Collection?> getCollection(String userId, String collectionId) async {
    final snapshot = await _tripsCollection(userId).doc(collectionId).get();
    if (!snapshot.exists) {
      return null;
    }
    return Collection.fromFirestore(snapshot);
  }

  @override
  Stream<Collection?> watchCollection(String userId, String collectionId) {
    return _tripsCollection(userId)
        .doc(collectionId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return Collection.fromFirestore(snapshot);
    });
  }

  @override
  Stream<List<Collection>> watchCollections(String userId) {
    return _tripsCollection(userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(Collection.fromFirestore).toList();
    });
  }

  @override
  Future<List<Collection>> getCollections(String userId) async {
    final snapshot = await _tripsCollection(userId)
        .orderBy('updatedAt', descending: true)
        .get();
    return snapshot.docs.map(Collection.fromFirestore).toList();
  }

  @override
  Stream<List<Receipt>> watchReceiptsForCollection(
    String userId,
    String collectionId,
  ) {
    return _receiptsCollection(userId)
        .where('collectionId', isEqualTo: collectionId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(Receipt.fromFirestore).toList();
    });
  }

  @override
  Future<List<Receipt>> getReceiptsForCollection(
    String userId,
    String collectionId,
  ) async {
    final snapshot = await _receiptsCollection(userId)
        .where('collectionId', isEqualTo: collectionId)
        .get();
    return snapshot.docs.map(Receipt.fromFirestore).toList();
  }
}
