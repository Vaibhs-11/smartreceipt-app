import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

@immutable
class ReceiptItem extends Equatable {
  final String name;
  final double price;

  const ReceiptItem({
    required this.name,
    required this.price,
  });

  Map<String, Object?> toMap() => {
        'name': name,
        'price': price,
      };

  factory ReceiptItem.fromMap(Map<String, Object?> map) {
    return ReceiptItem(
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [name, price];
}

@immutable
class Receipt extends Equatable {
  const Receipt({
    required this.id,
    required this.storeName,
    required this.date,
    required this.total,
    required this.currency,
    this.notes,
    this.tags = const <String>[],
    this.imagePath,
    this.extractedText,
    this.expiryDate,
    this.fileUrl,
    this.items = const <ReceiptItem>[],
  });

  final String id;
  final String storeName;
  final DateTime date;
  final double total;
  final String currency;
  final String? notes;
  final List<String> tags;
  final String? imagePath;      // local path if saved on device
  final String? extractedText;
  final DateTime? expiryDate;
  final String? fileUrl;        // cloud URL (Firebase Storage, etc.)
  final List<ReceiptItem> items;

  Receipt copyWith({
    String? id,
    String? storeName,
    DateTime? date,
    double? total,
    String? currency,
    String? notes,
    List<String>? tags,
    String? imagePath,
    String? extractedText,
    DateTime? expiryDate,
    String? fileUrl,
    List<ReceiptItem>? items,
  }) {
    return Receipt(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      date: date ?? this.date,
      total: total ?? this.total,
      currency: currency ?? this.currency,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      imagePath: imagePath ?? this.imagePath,
      extractedText: extractedText ?? this.extractedText,
      expiryDate: expiryDate ?? this.expiryDate,
      fileUrl: fileUrl ?? this.fileUrl,
      items: items ?? this.items,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'storeName': storeName,
      'date': Timestamp.fromDate(date),
      'total': total,
      'currency': currency,
      'notes': notes,
      'tags': tags,
      'imagePath': imagePath,
      'extractedText': extractedText,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'fileUrl': fileUrl,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }

  static Receipt fromMap(Map<String, Object?> map) {
    return Receipt(
      id: map['id']! as String,
      storeName: map['storeName']! as String,
      date: (map['date'] as Timestamp).toDate(),
      total: (map['total']! as num).toDouble(),
      currency: map['currency']! as String,
      notes: map['notes'] as String?,
      tags: (map['tags'] as List<Object?>?)?.cast<String>() ?? const <String>[],
      imagePath: map['imagePath'] as String?,
      extractedText: map['extractedText'] as String?,
      expiryDate: map['expiryDate'] != null
          ? (map['expiryDate'] as Timestamp).toDate()
          : null,
      fileUrl: map['fileUrl'] as String?,
      items: (map['items'] as List<dynamic>?)
              ?.map((i) => ReceiptItem.fromMap(Map<String, Object?>.from(i)))
              .toList() ??
          const [],
    );
  }

  /// Factory used by your repository
  factory Receipt.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Receipt.fromFirestore(doc);
  }

  factory Receipt.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError("Missing data for receipt ID: ${doc.id}");
    }

    return Receipt(
      id: doc.id,
      storeName: data['storeName'] as String? ?? "Unknown Store",
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] as String? ?? "USD",
      notes: data['notes'] as String?,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      imagePath: data['imagePath'] as String?,
      extractedText: data['extractedText'] as String?,
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
      fileUrl: data['fileUrl'] as String?,
      items: (data['items'] as List<dynamic>?)
              ?.map((i) => ReceiptItem.fromMap(Map<String, Object?>.from(i)))
              .toList() ??
          const [],
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeName,
        date,
        total,
        currency,
        notes,
        tags,
        imagePath,
        extractedText,
        expiryDate,
        fileUrl,
        items,
      ];
}
