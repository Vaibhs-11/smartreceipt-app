import 'package:cloud_firestore/cloud_firestore.dart';

class ReceiptItem {
  final String name;
  final double price;
  final bool taxClaimable;

  ReceiptItem({
    required this.name,
    required this.price,
    this.taxClaimable = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'taxClaimable': taxClaimable,
    };
  }

  factory ReceiptItem.fromMap(Map<String, dynamic> map) {
    return ReceiptItem(
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      taxClaimable: map['taxClaimable'] as bool? ?? false,
    );
  }

  ReceiptItem copyWith({
    String? name,
    double? price,
    bool? taxClaimable,
  }) {
    return ReceiptItem(
      name: name ?? this.name,
      price: price ?? this.price,
      taxClaimable: taxClaimable ?? this.taxClaimable,
    );
  }
}

class Receipt {
  final String id;
  final String storeName;
  final double amount; // total
  final DateTime date;
  final String? fileUrl;
  final List<ReceiptItem> items;

  Receipt({
    required this.id,
    required this.storeName,
    required this.amount,
    required this.date,
    this.fileUrl,
    this.items = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'storeName': storeName,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'fileUrl': fileUrl,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }

  factory Receipt.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Receipt(
      id: doc.id,
      storeName: data['storeName'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      date: (data['date'] as Timestamp).toDate(),
      fileUrl: data['fileUrl'] as String?,
      items: (data['items'] as List<dynamic>?)
              ?.map((i) => ReceiptItem.fromMap(Map<String, dynamic>.from(i)))
              .toList() ??
          const [],
    );
  }
}
