import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<void> addReceipt({
    required String storeName,
    required double amount,
    DateTime? date,
    String? fileUrl, // For uploaded digital receipts later
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      print("⚠️ No user signed in");
      return;
    }

    final receiptsRef = _db
        .collection("users")
        .doc(user.uid)
        .collection("receipts");

    await receiptsRef.add({
      "storeName": storeName,
      "amount": amount,
      "date": date ?? DateTime.now(),
      "fileUrl": fileUrl,
    });

    print("✅ Receipt added!");
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getReceipts() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return _db
        .collection("users")
        .doc(user.uid)
        .collection("receipts")
        .orderBy("date", descending: true)
        .snapshots();
  }
}
class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Future<User?> signInAnonymously() async {
    final userCredential = await _auth.signInAnonymously();
    return userCredential.user;
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Stream<User?> get onAuthStateChanged => _auth.authStateChanges();
}