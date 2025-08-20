import 'package:cloud_firestore/cloud_firestore.dart';

class Receipt {
  final String id;
  final String storeName;
  final double amount;
  final DateTime date;
  final String? fileUrl;

  Receipt({
    required this.id,
    required this.storeName,
    required this.amount,
    required this.date,
    this.fileUrl,
  });

  factory Receipt.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Receipt(
      id: doc.id,
      storeName: data['storeName'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      fileUrl: data['fileUrl'],
    );
  }
}
