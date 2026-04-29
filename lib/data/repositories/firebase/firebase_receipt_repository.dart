import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:receiptnest/core/utils/app_logger.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/repositories/receipt_repository.dart';

/// Firebase implementation of ReceiptRepository
class FirebaseReceiptRepository implements ReceiptRepository {
  FirebaseReceiptRepository();

  static const String _updatedAtField = 'updatedAt';

  CollectionReference<Map<String, dynamic>> _receiptsCollection(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('receipts');
  }

  String? _uid() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  Future<int> getReceiptCount() async {
    final uid = _uid();
    if (uid == null) {
      return 0;
    }
    final querySnapshot = await _receiptsCollection(uid).count().get();
    return querySnapshot.count ?? 0;
  }

  // ---------------------------------------------------------------------------
  // ADD RECEIPT
  // ---------------------------------------------------------------------------
  @override
  Future<void> addReceipt(Receipt receipt) async {
    if (_uid() == null) {
      AppLogger.log('Skipping addReceipt: user not logged in.');
      return;
    }
    final sanitized = receipt.copyWith(
      items: sanitizeReceiptItems(receipt.items),
    );
    final callable = FirebaseFunctions.instance.httpsCallable('createReceipt');
    final payload = {
      ...sanitized.toMap(),
      'date': sanitized.date.toUtc().toIso8601String(),
    };

    await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'receiptId': sanitized.id,
      'receipt': payload,
    });
  }

  // ---------------------------------------------------------------------------
  // GET ALL RECEIPTS
  // ---------------------------------------------------------------------------
  Future<List<Receipt>> getAllReceipts() async {
    final uid = _uid();
    if (uid == null) {
      return [];
    }

    final query = await _receiptsCollection(uid)
        .orderBy('createdAt', descending: true)
        .get();

    return query.docs.map(Receipt.fromFirestore).toList();
  }

  @override
  Future<List<Receipt>> getReceipts() {
    return getAllReceipts();
  }

  // ---------------------------------------------------------------------------
  // GET RECEIPT BY ID
  // ---------------------------------------------------------------------------
  @override
  Future<Receipt?> getReceiptById(String id) async {
    final uid = _uid();
    if (uid == null) {
      return null;
    }

    final doc = await _receiptsCollection(uid).doc(id).get();
    if (!doc.exists) return null;

    return Receipt.fromFirestore(doc);
  }

  // ---------------------------------------------------------------------------
  // UPDATE RECEIPT
  // ---------------------------------------------------------------------------
  @override
  Future<void> updateReceipt(Receipt receipt) async {
    final uid = _uid();
    if (uid == null) {
      AppLogger.log('Skipping updateReceipt: user not logged in.');
      return;
    }

    final sanitized = receipt.copyWith(
      items: sanitizeReceiptItems(receipt.items),
    );

    await _receiptsCollection(uid).doc(sanitized.id).update(sanitized.toMap());
  }

  // ---------------------------------------------------------------------------
  // DELETE RECEIPT
  // ---------------------------------------------------------------------------
  @override
  Future<void> deleteReceipt(String id) async {
    final uid = _uid();
    if (uid == null) {
      AppLogger.log('Skipping deleteReceipt: user not logged in.');
      return;
    }
    await _receiptsCollection(uid).doc(id).delete();
  }

  @override
  Future<void> assignReceiptsToCollection(
    List<String> receiptIds,
    String collectionId,
  ) async {
    final uid = _uid();
    if (uid == null || receiptIds.isEmpty) {
      AppLogger.log(
          'Skipping assignReceiptsToCollection: missing user or ids.');
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final receiptId in receiptIds) {
      batch.update(_receiptsCollection(uid).doc(receiptId), <String, Object?>{
        'collectionId': collectionId,
        _updatedAtField: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> removeReceiptFromCollection(String receiptId) async {
    await removeReceiptsFromCollection(<String>[receiptId]);
  }

  @override
  Future<void> removeReceiptsFromCollection(List<String> receiptIds) async {
    final uid = _uid();
    if (uid == null || receiptIds.isEmpty) {
      AppLogger.log(
        'Skipping removeReceiptsFromCollection: missing user or ids.',
      );
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final receiptId in receiptIds) {
      batch.update(_receiptsCollection(uid).doc(receiptId), <String, Object?>{
        'collectionId': null,
        _updatedAtField: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> moveReceiptToCollection(
    String receiptId,
    String newCollectionId,
  ) {
    return assignReceiptsToCollection(<String>[receiptId], newCollectionId);
  }
}
