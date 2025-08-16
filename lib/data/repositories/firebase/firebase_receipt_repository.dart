import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

class FirebaseReceiptRepository implements ReceiptRepository {
  FirebaseReceiptRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _receipts => _db.collection('receipts');

  @override
  Future<void> addReceipt(Receipt receipt) async {
    await _receipts.doc(receipt.id).set(receipt.toMap());
  }

  @override
  Future<void> deleteReceipt(String id) async {
    await _receipts.doc(id).delete();
  }

  @override
  Future<List<Receipt>> getAllReceipts() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _receipts.orderBy('date', descending: true).get();
    return snap.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) => Receipt.fromMap(d.data())).toList();
  }

  @override
  Future<Receipt?> getReceiptById(String id) async {
    final DocumentSnapshot<Map<String, dynamic>> doc = await _receipts.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Receipt.fromMap(doc.data()!);
  }

  @override
  Future<void> updateReceipt(Receipt receipt) async {
    await _receipts.doc(receipt.id).update(receipt.toMap());
  }
}



