import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

/// Firebase implementation of ReceiptRepository
class FirebaseReceiptRepository implements ReceiptRepository {
  FirebaseReceiptRepository();

  CollectionReference<Map<String, dynamic>> _receiptsCollection(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('receipts');
  }

  String _uid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }
    return user.uid;
  }

  // ---------------------------------------------------------------------------
  // ADD RECEIPT
  // ---------------------------------------------------------------------------
  @override
  Future<void> addReceipt(Receipt receipt) async {
    final uid = _uid();

    await _receiptsCollection(uid)
        .doc(receipt.id)
        .set({
          ...receipt.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  // ---------------------------------------------------------------------------
  // GET ALL RECEIPTS
  // ---------------------------------------------------------------------------
  @override
  Future<List<Receipt>> getAllReceipts() async {
    final uid = _uid();

    final query = await _receiptsCollection(uid)
        .orderBy('createdAt', descending: true)
        .get();

    return query.docs
        .map((doc) => Receipt.fromFirestore(doc))
        .toList();
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

    await _receiptsCollection(uid)
        .doc(receipt.id)
        .update(receipt.toMap());
  }

  // ---------------------------------------------------------------------------
  // DELETE RECEIPT
  // ---------------------------------------------------------------------------
  @override
  Future<void> deleteReceipt(String id) async {
    final uid = _uid();
    await _receiptsCollection(uid).doc(id).delete();
  }
}
