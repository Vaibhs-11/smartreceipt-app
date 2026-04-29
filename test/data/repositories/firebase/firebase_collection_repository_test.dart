import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/data/repositories/firebase/firebase_collection_repository.dart';
import 'package:receiptnest/domain/entities/collection.dart';

void main() {
  const userId = 'user-1';

  group('FirebaseCollectionRepository', () {
    test('createCollection and getCollection round-trip the model', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseCollectionRepository(firestore: firestore);
      final collection = Collection(
        id: 'collection-1',
        name: 'Work Travel',
        type: CollectionType.work,
        status: CollectionStatus.active,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      await repository.createCollection(userId, collection);
      final result = await repository.getCollection(userId, 'collection-1');

      expect(result, isNotNull);
      expect(result!.id, 'collection-1');
      expect(result.name, 'Work Travel');
      expect(result.type, CollectionType.work);
      expect(result.status, CollectionStatus.active);
    });

    test('watchCollections maps firestore docs into Collection models',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseCollectionRepository(firestore: firestore);

      final future = repository.watchCollections(userId).firstWhere(
            (collections) => collections.isNotEmpty,
          );

      await firestore.collection('users').doc(userId).collection('trips').add(
        <String, Object?>{
          'name': 'Personal Event',
          'type': 'personal',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 2)),
        },
      );

      final collections = await future.timeout(const Duration(seconds: 2));

      expect(collections, hasLength(1));
      expect(collections.single.name, 'Personal Event');
      expect(collections.single.type, CollectionType.personal);
      expect(collections.single.status, CollectionStatus.completed);
    });

    test('deleteCollection unlinks receipts before deleting the document',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirebaseCollectionRepository(firestore: firestore);

      await firestore
          .collection('users')
          .doc(userId)
          .collection('trips')
          .doc(
            'collection-1',
          )
          .set(<String, Object?>{
        'name': 'Collection',
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
        'collectionId': 'collection-1',
      });

      await repository.deleteCollection(userId, 'collection-1');

      final collectionDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('trips')
          .doc('collection-1')
          .get();
      final receiptDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('receipts')
          .doc('receipt-1')
          .get();

      expect(collectionDoc.exists, isFalse);
      expect(receiptDoc.data()!['collectionId'], isNull);
    });
  });
}
