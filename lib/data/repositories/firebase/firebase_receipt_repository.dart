import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

class FirebaseReceiptRepository implements ReceiptRepository {
  FirebaseReceiptRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  /// Scoped collection: /users/{uid}/receipts
  CollectionReference<Map<String, dynamic>> get _receipts {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("No user logged in");
    }
    return _db.collection('users').doc(user.uid).collection('receipts');
  }

  @override
  Future<void> addReceipt(Receipt receipt) async {
    await _receipts.doc(receipt.id).set(receipt.toMap());
  }

  @override
  Future<void> deleteReceipt(String id) async {
    final docRef = _receipts.doc(id);
    final doc = await docRef.get();

    if (!doc.exists) {
      throw Exception("Receipt $id not found");
    }

    // Delete associated file from Firebase Storage if exists
    final fileUrl = doc.data()?['fileUrl'] as String?;
    if (fileUrl != null && fileUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(fileUrl).delete();
      } catch (e) {
        // Non-fatal: log error but continue deleting Firestore doc
        print(
          "⚠️ Warning: Failed to delete file from storage for receipt $id: $e",
        );
      }
    }

    // Delete receipt document from Firestore
    await docRef.delete();
  }

  @override
  Future<List<Receipt>> getAllReceipts() async {
    final snap = await _receipts.orderBy('date', descending: true).get();
    return snap.docs.map((d) => Receipt.fromDocument(d)).toList();
  }

  @override
  Future<Receipt?> getReceiptById(String id) async {
    final doc = await _receipts.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Receipt.fromDocument(doc);
  }

  @override
  Future<void> updateReceipt(Receipt receipt) async {
    await _receipts.doc(receipt.id).update(receipt.toMap());
  }
}
