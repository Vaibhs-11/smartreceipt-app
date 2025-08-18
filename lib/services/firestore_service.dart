import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  Future<void> addReceipt(Map<String, dynamic> receiptData) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('receipts')
        .add(receiptData);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getReceipts() {
    return _db
        .collection('users')
        .doc(_uid)
        .collection('receipts')
        .snapshots();
  }
}
