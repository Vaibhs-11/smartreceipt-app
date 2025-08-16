import 'package:equatable/equatable.dart';

class Receipt extends Equatable {
  Receipt({
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
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'storeName': storeName,
      'date': date.toIso8601String(),
      'total': total,
      'currency': currency,
      'notes': notes,
      'tags': tags,
      'imagePath': imagePath,
      'extractedText': extractedText,
      'expiryDate': expiryDate?.toIso8601String(),
    };
  }

  static Receipt fromMap(Map<String, Object?> map) {
    return Receipt(
      id: map['id']! as String,
      storeName: map['storeName']! as String,
      date: DateTime.parse(map['date']! as String),
      total: (map['total']! as num).toDouble(),
      currency: map['currency']! as String,
      notes: map['notes'] as String?,
      tags: (map['tags'] as List<Object?>?)?.cast<String>() ?? const <String>[],
      imagePath: map['imagePath'] as String?,
      extractedText: map['extractedText'] as String?,
      expiryDate: (map['expiryDate'] as String?) != null
          ? DateTime.parse(map['expiryDate']! as String)
          : null,
    );
  }

  @override
  List<Object?> get props => <Object?>[id, storeName, date, total, currency, notes, tags, imagePath, extractedText, expiryDate];
}


