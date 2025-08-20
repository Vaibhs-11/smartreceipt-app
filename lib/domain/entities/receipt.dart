import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

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
  });

  final String id;
  final String storeName;
  final DateTime date;
  final double total;
  final String currency;
  final String? notes;
  final List<String> tags;
  final String? imagePath;
  final String? extractedText;
  final DateTime? expiryDate;
  final String? fileUrl; // ✅ Added missing field

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
    String? fileUrl, // ✅ Include in copyWith
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
    );
  }

  factory Receipt.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Receipt.fromMap({
      'id': doc.id,
      'storeName': data['storeName'],
      'date': data['date'],
      'total': data['total'],
      'currency': data['currency'],
      'notes': data['notes'],
      'tags': data['tags'],
      'imagePath': data['imagePath'],
      'extractedText': data['extractedText'],
      'expiryDate': data['expiryDate'],
      'fileUrl': data['fileUrl'],
    });
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
      ];
factory Receipt.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  if (data == null) {
    throw StateError("Missing data for receipt ID: ${doc.id}");
  }

  return Receipt(
    id: doc.id,
    storeName: data['storeName'] as String? ?? "Unknown Store",
    date: data['date'] != null
        ? DateTime.tryParse(data['date'].toString()) ?? DateTime.now()
        : DateTime.now(),
    total: (data['amount'] as num?)?.toDouble() ?? 0.0,
    currency: data['currency'] as String? ?? "USD",
    notes: data['notes'] as String?,
    tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    imagePath: data['fileUrl'] as String?, // matches addReceipt()
    extractedText: data['extractedText'] as String?,
    expiryDate: data['expiryDate'] != null
        ? DateTime.tryParse(data['expiryDate'].toString())
        : null,
  );
}
}
