import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';

class FirestoreService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  FirestoreService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  /// Adds a new receipt under the current user's collection
  Future<void> addReceipt({
    required String storeName,
    required double amount,
    DateTime? date,
    String? fileUrl,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      debugPrint("⚠️ No user signed in, cannot add receipt.");
      return;
    }

    try {
      final receiptsRef = _db
          .collection("users")
          .doc(user.uid)
          .collection("receipts");

      await receiptsRef.add({
        "storeName": storeName,
        "amount": amount,
        "date": (date ?? DateTime.now()).toIso8601String(),
        "fileUrl": fileUrl,
        "createdAt": FieldValue.serverTimestamp(), // server clock
      });

      debugPrint("✅ Receipt added successfully for user: ${user.uid}");
    } catch (e, stackTrace) {
      debugPrint("❌ Failed to add receipt: $e");
      debugPrintStack(stackTrace: stackTrace);
      rethrow; // let UI decide how to handle
    }
  }

  /// Stream of receipts for the current user
  Stream<List<Receipt>> getReceipts() {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint("⚠️ No user signed in, returning empty receipt stream.");
      return const Stream.empty();
    }

    return _db
        .collection("users")
        .doc(user.uid)
        .collection("receipts")
        .orderBy("date", descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Receipt.fromFirestore(doc))
              .toList();
        });
  }

  /// Deletes a receipt by document ID
  Future<void> deleteReceipt(String receiptId) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint("⚠️ No user signed in, cannot delete receipt.");
      return;
    }

    try {
      await _db
          .collection("users")
          .doc(user.uid)
          .collection("receipts")
          .doc(receiptId)
          .delete();

      debugPrint("🗑️ Receipt $receiptId deleted successfully.");
    } catch (e, stackTrace) {
      debugPrint("❌ Failed to delete receipt: $e");
      debugPrintStack(stackTrace: stackTrace);
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
      debugPrint("⚠️ No user signed in, cannot update receipt.");
      return;
    }

    try {
      final updates = <String, dynamic>{};

      if (storeName != null) updates["storeName"] = storeName;
      if (amount != null) updates["amount"] = amount;
      if (date != null) updates["date"] = date.toIso8601String();
      if (fileUrl != null) updates["fileUrl"] = fileUrl;

      if (updates.isEmpty) {
        debugPrint("⚠️ No updates provided, skipping update.");
        return;
      }

      await _db
          .collection("users")
          .doc(user.uid)
          .collection("receipts")
          .doc(receiptId)
          .update(updates);

      debugPrint("✏️ Receipt $receiptId updated successfully.");
    } catch (e, stackTrace) {
      debugPrint("❌ Failed to update receipt: $e");
      debugPrintStack(stackTrace: stackTrace);
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