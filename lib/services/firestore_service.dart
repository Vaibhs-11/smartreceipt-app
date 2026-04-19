import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:receiptnest/core/utils/app_logger.dart';
import 'package:receiptnest/domain/entities/receipt.dart';

class FirestoreService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  FirestoreService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Adds a new receipt under the current user's collection
  Future<void> addReceipt({
    required String storeName,
    required double amount,
    DateTime? date,
    String? fileUrl,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      AppLogger.log('Cannot add receipt: no user signed in.');
      return;
    }

    try {
      final receiptsRef =
          _db.collection("users").doc(user.uid).collection("receipts");

      await receiptsRef.add({
        "storeName": storeName,
        "amount": amount,
        "date": (date ?? DateTime.now()).toIso8601String(),
        "fileUrl": fileUrl,
        "createdAt": FieldValue.serverTimestamp(), // server clock
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add receipt: $e\n$stackTrace');
      rethrow; // let UI decide how to handle
    }
  }

  /// Stream of receipts for the current user
  Stream<List<Receipt>> getReceipts() {
    final user = _auth.currentUser;
    if (user == null) {
      AppLogger.log('Returning empty receipt stream: no user signed in.');
      return const Stream.empty();
    }
    AppLogger.log('Fetching receipts for current user');
    return _db
        .collection("users")
        .doc(user.uid)
        .collection("receipts")
        .orderBy("date", descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Receipt.fromFirestore(doc)).toList();
    });
  }

  /// Deletes a receipt by document ID
  Future<void> deleteReceipt(String receiptId) async {
    final user = _auth.currentUser;
    if (user == null) {
      AppLogger.log('Cannot delete receipt: no user signed in.');
      return;
    }

    try {
      await _db
          .collection("users")
          .doc(user.uid)
          .collection("receipts")
          .doc(receiptId)
          .delete();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete receipt: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Updates an existing receipt
  Future<void> updateReceipt(
    String receiptId, {
    String? storeName,
    double? amount,
    DateTime? date,
    String? fileUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      AppLogger.log('Cannot update receipt: no user signed in.');
      return;
    }

    try {
      final updates = <String, dynamic>{};

      if (storeName != null) updates["storeName"] = storeName;
      if (amount != null) updates["amount"] = amount;
      if (date != null) updates["date"] = date.toIso8601String();
      if (fileUrl != null) updates["fileUrl"] = fileUrl;

      if (updates.isEmpty) {
        AppLogger.log('Skipping receipt update: no changes provided.');
        return;
      }

      await _db
          .collection("users")
          .doc(user.uid)
          .collection("receipts")
          .doc(receiptId)
          .update(updates);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update receipt: $e\n$stackTrace');
      rethrow;
    }
  }
}

//class FirebaseAuthService implements AuthService {
//  final FirebaseAuth _auth = FirebaseAuth.instance;

//  @override
//  Future<User?> signInAnonymously() async {
//    final userCredential = await _auth.signInAnonymously();
//    return userCredential.user;
//  }

// @override
// Future<void> signOut() async {
//   await _auth.signOut();
// }

//@override
//Stream<User?> get onAuthStateChanged => _auth.authStateChanges();
//}
