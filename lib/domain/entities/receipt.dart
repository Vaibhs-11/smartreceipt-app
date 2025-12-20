import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

@immutable
class ReceiptItem extends Equatable {
  final String name;
  final double price;
  final bool taxClaimable;

  const ReceiptItem({
    required this.name,
    required this.price,
    this.taxClaimable = false,
  });

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

  Map<String, Object?> toMap() => {
        'name': name,
        'price': price,
        'taxClaimable': taxClaimable,
      };

  factory ReceiptItem.fromMap(Map<String, Object?> map) {
    return ReceiptItem(
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      taxClaimable: map['taxClaimable'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [name, price, taxClaimable];
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
    this.originalImagePath,
    this.processedImagePath,
    this.imageProcessingStatus,
    this.extractedText,
    this.expiryDate,
    this.fileUrl,
    this.items = const <ReceiptItem>[],
    this.searchKeywords = const <String>[],
    this.normalizedBrand,
    this.category,
  });

  final String id; // Firestore doc ID
  final String storeName;
  final DateTime date;
  final double total;
  final String currency;
  final String? notes;
  final List<String> tags;
  final String? imagePath;
  final String? originalImagePath;
  final String? processedImagePath;
  final String? imageProcessingStatus;
  final String? extractedText;
  final DateTime? expiryDate;
  final String? fileUrl;
  final List<ReceiptItem> items;
  final List<String> searchKeywords;
  final String? normalizedBrand;
  final String? category;

  Receipt copyWith({
    String? id,
    String? storeName,
    DateTime? date,
    double? total,
    String? currency,
    String? notes,
    List<String>? tags,
    String? imagePath,
    String? originalImagePath,
    String? processedImagePath,
    String? imageProcessingStatus,
    String? extractedText,
    DateTime? expiryDate,
    String? fileUrl,
    List<ReceiptItem>? items,
    List<String>? searchKeywords,
    String? normalizedBrand,
    String? category,
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
      originalImagePath: originalImagePath ?? this.originalImagePath,
      processedImagePath: processedImagePath ?? this.processedImagePath,
      imageProcessingStatus:
          imageProcessingStatus ?? this.imageProcessingStatus,
      extractedText: extractedText ?? this.extractedText,
      expiryDate: expiryDate ?? this.expiryDate,
      fileUrl: fileUrl ?? this.fileUrl,
      items: items ?? this.items,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      normalizedBrand: normalizedBrand ?? this.normalizedBrand,
      category: category ?? this.category,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'storeName': storeName,
      'date': Timestamp.fromDate(date),
      'total': total,
      'currency': currency,
      'notes': notes,
      'tags': tags,
      'imagePath': imagePath,
      'originalImagePath': originalImagePath,
      'processedImagePath': processedImagePath,
      'imageProcessingStatus': imageProcessingStatus,
      'extractedText': extractedText,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'fileUrl': fileUrl,
      'items': items.map((i) => i.toMap()).toList(),
      'searchKeywords': searchKeywords,
      'normalizedBrand': normalizedBrand,
      'category': category,
    };
  }

  /// Only use this if mapping raw maps (non-Firestore).
  static Receipt fromMap(Map<String, Object?> map, {String? id}) {
    return Receipt(
      id: id ?? (map['id'] as String? ?? ''),
      storeName: map['storeName'] as String? ?? '',
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] as String? ?? "AUD",
      notes: map['notes'] as String?,
      tags: (map['tags'] as List<Object?>?)?.cast<String>() ?? const [],
      imagePath: map['imagePath'] as String?,
      originalImagePath: map['originalImagePath'] as String?,
      processedImagePath: map['processedImagePath'] as String?,
      imageProcessingStatus: map['imageProcessingStatus'] as String?,
      extractedText: map['extractedText'] as String?,
      expiryDate: (map['expiryDate'] as Timestamp?)?.toDate(),
      fileUrl: map['fileUrl'] as String?,
      items: (map['items'] as List<dynamic>?)
              ?.map((i) => ReceiptItem.fromMap(
                  Map<String, Object?>.from(i as Map<dynamic, dynamic>)))
              .toList() ??
          const [],
      searchKeywords:
          (map['searchKeywords'] as List<dynamic>?)?.cast<String>() ?? const [],
      normalizedBrand: map['normalizedBrand'] as String?,
      category: map['category'] as String?,
    );
  }

  /// Recommended: construct directly from Firestore docs
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
      currency: data['currency'] as String? ?? "AUD",
      notes: data['notes'] as String?,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      imagePath: data['imagePath'] as String?,
      originalImagePath: data['originalImagePath'] as String?,
      processedImagePath: data['processedImagePath'] as String?,
      imageProcessingStatus: data['imageProcessingStatus'] as String?,
      extractedText: data['extractedText'] as String?,
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
      fileUrl: data['fileUrl'] as String?,
      items: (data['items'] as List<dynamic>?)
              ?.map((i) => ReceiptItem.fromMap(
                  Map<String, Object?>.from(i as Map<dynamic, dynamic>)))
              .toList() ??
          const [],
      searchKeywords:
          (data['searchKeywords'] as List<dynamic>?)?.cast<String>() ??
              const [],
      normalizedBrand: data['normalizedBrand'] as String?,
      category: data['category'] as String?,
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
        originalImagePath,
        processedImagePath,
        imageProcessingStatus,
        extractedText,
        expiryDate,
        fileUrl,
        items,
        searchKeywords,
        normalizedBrand,
        category,
      ];
}
