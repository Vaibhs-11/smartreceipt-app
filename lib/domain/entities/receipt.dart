import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Filters out receipt items that have no price or a non-positive price.
List<ReceiptItem> sanitizeReceiptItems(List<ReceiptItem> items) {
  return items.where((item) => item.price != null && item.price! > 0).toList();
}

@immutable
class ReceiptItem extends Equatable {
  static const Object _noChange = Object();

  final String name;
  final double? price;
  final bool taxClaimable;
  final double? quantity;
  final double? unitPrice;
  final String? category;
  final String? brand;
  final String? canonicalName;
  final String? collectionCategory;
  final String? manualCollectionCategory;
  final int? collectionEnrichmentVersion;
  final List<String> searchTokens;
  final int? enrichmentVersion;
  final ReceiptItemManualOverrides? manualOverrides;

  const ReceiptItem({
    required this.name,
    required this.price,
    this.taxClaimable = false,
    this.quantity,
    this.unitPrice,
    this.category,
    this.brand,
    this.canonicalName,
    this.collectionCategory,
    this.manualCollectionCategory,
    this.collectionEnrichmentVersion,
    this.searchTokens = const <String>[],
    this.enrichmentVersion,
    this.manualOverrides,
  });

  ReceiptItem copyWith({
    String? name,
    Object? price = _noChange,
    bool? taxClaimable,
    double? quantity,
    double? unitPrice,
    String? category,
    String? brand,
    String? canonicalName,
    Object? collectionCategory = _noChange,
    Object? manualCollectionCategory = _noChange,
    Object? collectionEnrichmentVersion = _noChange,
    List<String>? searchTokens,
    int? enrichmentVersion,
    ReceiptItemManualOverrides? manualOverrides,
  }) {
    return ReceiptItem(
      name: name ?? this.name,
      price: identical(price, _noChange) ? this.price : price as double?,
      taxClaimable: taxClaimable ?? this.taxClaimable,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      canonicalName: canonicalName ?? this.canonicalName,
      collectionCategory: identical(collectionCategory, _noChange)
          ? this.collectionCategory
          : collectionCategory as String?,
      manualCollectionCategory: identical(manualCollectionCategory, _noChange)
          ? this.manualCollectionCategory
          : manualCollectionCategory as String?,
      collectionEnrichmentVersion:
          identical(collectionEnrichmentVersion, _noChange)
              ? this.collectionEnrichmentVersion
              : collectionEnrichmentVersion as int?,
      searchTokens: searchTokens ?? this.searchTokens,
      enrichmentVersion: enrichmentVersion ?? this.enrichmentVersion,
      manualOverrides: manualOverrides ?? this.manualOverrides,
    );
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'name': name,
      'price': price,
      'taxClaimable': taxClaimable,
      'search_tokens': searchTokens,
    };
    if (quantity != null) {
      map['quantity'] = quantity;
    }
    if (unitPrice != null) {
      map['unitPrice'] = unitPrice;
    }
    if (category != null) {
      map['category'] = category;
    }
    if (brand != null) {
      map['brand'] = brand;
    }
    if (canonicalName != null) {
      map['canonical_name'] = canonicalName;
    }
    if (collectionCategory != null) {
      map['collection_category'] = collectionCategory;
    }
    if (manualCollectionCategory != null) {
      map['manual_collection_category'] = manualCollectionCategory;
    }
    if (collectionEnrichmentVersion != null) {
      map['collection_enrichment_version'] = collectionEnrichmentVersion;
    }
    if (enrichmentVersion != null) {
      map['enrichment_version'] = enrichmentVersion;
    }
    if (manualOverrides != null) {
      map['manual_overrides'] = manualOverrides!.toMap();
    }
    return map;
  }

  factory ReceiptItem.fromMap(Map<String, Object?> map) {
    final rawSearchTokens = map['search_tokens'];
    final safeSearchTokens = rawSearchTokens is List<dynamic>
        ? rawSearchTokens.whereType<String>().toList()
        : const <String>[];

    return ReceiptItem(
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble(),
      taxClaimable: map['taxClaimable'] as bool? ?? false,
      quantity: (map['quantity'] as num?)?.toDouble(),
      unitPrice: (map['unitPrice'] as num?)?.toDouble(),
      category: map['category'] as String?,
      brand: map['brand'] as String?,
      canonicalName: map['canonical_name'] as String?,
      collectionCategory: map['collection_category'] as String?,
      manualCollectionCategory: map['manual_collection_category'] as String?,
      collectionEnrichmentVersion:
          (map['collection_enrichment_version'] as num?)?.toInt(),
      searchTokens: safeSearchTokens,
      enrichmentVersion: (map['enrichment_version'] as num?)?.toInt(),
      manualOverrides: map['manual_overrides'] is Map
          ? ReceiptItemManualOverrides.fromMap(
              Map<dynamic, dynamic>.from(
                map['manual_overrides'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
    );
  }

  @override
  List<Object?> get props => [
        name,
        price,
        taxClaimable,
        quantity,
        unitPrice,
        category,
        brand,
        canonicalName,
        collectionCategory,
        manualCollectionCategory,
        collectionEnrichmentVersion,
        searchTokens,
        enrichmentVersion,
        manualOverrides,
      ];
}

@immutable
class ReceiptItemManualOverrides extends Equatable {
  final bool category;
  final bool brand;
  final bool canonicalName;

  const ReceiptItemManualOverrides({
    this.category = false,
    this.brand = false,
    this.canonicalName = false,
  });

  factory ReceiptItemManualOverrides.fromMap(Map<dynamic, dynamic> map) {
    return ReceiptItemManualOverrides(
      category: map['category'] as bool? ?? false,
      brand: map['brand'] as bool? ?? false,
      canonicalName: map['canonical_name'] as bool? ?? false,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'category': category,
      'brand': brand,
      'canonical_name': canonicalName,
    };
  }

  @override
  List<Object?> get props => [category, brand, canonicalName];
}

@immutable
class Receipt extends Equatable {
  static const Object _noChange = Object();

  const Receipt({
    required this.id,
    required this.storeName,
    required this.date,
    required this.total,
    required this.currency,
    this.receiptType = 'personal',
    this.receiptTaxAmount,
    this.collectionId,
    this.businessSubtotal,
    this.businessTaxAmount,
    this.businessTotal,
    this.notes,
    this.tags = const <String>[],
    this.imagePath,
    this.originalImagePath,
    this.processedImagePath,
    this.imageProcessingStatus,
    this.extractedText,
    this.fileUrl,
    this.enrichment,
    this.collectionEnrichment,
    this.items = const <ReceiptItem>[],
    this.searchKeywords = const <String>[],
    this.normalizedBrand,
    this.metadata,
  });

  final String id; // Firestore doc ID
  final String storeName;
  final DateTime date;

  /// Total amount paid for the receipt, including tax.
  final double total;
  final String currency;
  final String receiptType;

  /// Tax amount on the receipt, in the same currency as [total].
  final double? receiptTaxAmount;
  final String? collectionId;
  final double? businessSubtotal;
  final double? businessTaxAmount;
  final double? businessTotal;
  final String? notes;
  final List<String> tags;
  final String? imagePath;
  final String? originalImagePath;
  final String? processedImagePath;
  final String? imageProcessingStatus;
  final String? extractedText;
  final String? fileUrl;
  final ReceiptEnrichment? enrichment;
  final ReceiptCollectionEnrichment? collectionEnrichment;
  final List<ReceiptItem> items;
  final List<String> searchKeywords;
  final String? normalizedBrand;
  final Map<String, Object?>? metadata;

  Receipt copyWith({
    String? id,
    String? storeName,
    DateTime? date,
    double? total,
    String? currency,
    String? receiptType,
    double? receiptTaxAmount,
    Object? collectionId = _noChange,
    double? businessSubtotal,
    double? businessTaxAmount,
    double? businessTotal,
    String? notes,
    List<String>? tags,
    String? imagePath,
    String? originalImagePath,
    String? processedImagePath,
    String? imageProcessingStatus,
    String? extractedText,
    String? fileUrl,
    ReceiptEnrichment? enrichment,
    Object? collectionEnrichment = _noChange,
    List<ReceiptItem>? items,
    List<String>? searchKeywords,
    String? normalizedBrand,
    Map<String, Object?>? metadata,
  }) {
    return Receipt(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      date: date ?? this.date,
      total: total ?? this.total,
      currency: currency ?? this.currency,
      receiptType: receiptType ?? this.receiptType,
      receiptTaxAmount: receiptTaxAmount ?? this.receiptTaxAmount,
      collectionId: identical(collectionId, _noChange)
          ? this.collectionId
          : collectionId as String?,
      businessSubtotal: businessSubtotal ?? this.businessSubtotal,
      businessTaxAmount: businessTaxAmount ?? this.businessTaxAmount,
      businessTotal: businessTotal ?? this.businessTotal,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      imagePath: imagePath ?? this.imagePath,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      processedImagePath: processedImagePath ?? this.processedImagePath,
      imageProcessingStatus:
          imageProcessingStatus ?? this.imageProcessingStatus,
      extractedText: extractedText ?? this.extractedText,
      fileUrl: fileUrl ?? this.fileUrl,
      enrichment: enrichment ?? this.enrichment,
      collectionEnrichment: identical(collectionEnrichment, _noChange)
          ? this.collectionEnrichment
          : collectionEnrichment as ReceiptCollectionEnrichment?,
      items: items ?? this.items,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      normalizedBrand: normalizedBrand ?? this.normalizedBrand,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toMap() {
    final cleanedItems = sanitizeReceiptItems(items);
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
      'fileUrl': fileUrl,
      'enrichment': enrichment?.toMap(),
      'collectionEnrichment': collectionEnrichment?.toMap(),
      'items': cleanedItems.map((i) => i.toMap()).toList(),
      'searchKeywords': searchKeywords,
      'normalizedBrand': normalizedBrand,
      'metadata': metadata,
      'receiptType': receiptType,
      'receiptTaxAmount': receiptTaxAmount,
      'collectionId': collectionId,
      'businessSubtotal': businessSubtotal,
      'businessTaxAmount': businessTaxAmount,
      'businessTotal': businessTotal,
    };
  }

  /// Only use this if mapping raw maps (non-Firestore).
  static Receipt fromMap(Map<String, Object?> map, {String? id}) {
    final rawEnrichment = map['enrichment'];
    final receiptEnrichment = rawEnrichment is Map
        ? ReceiptEnrichment.fromMap(
            Map<String, Object?>.from(rawEnrichment),
          )
        : null;
    final rawCollectionEnrichment = map['collectionEnrichment'];
    final ReceiptCollectionEnrichment? collectionEnrichment =
        rawCollectionEnrichment is Map
            ? ReceiptCollectionEnrichment.fromMap(
                Map<String, Object?>.from(rawCollectionEnrichment),
              )
            : null;

    return Receipt(
      id: id ?? (map['id'] as String? ?? ''),
      storeName: map['storeName'] as String? ?? '',
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] as String? ?? "AUD",
      receiptType: map['receiptType'] as String? ?? 'personal',
      receiptTaxAmount: (map['receiptTaxAmount'] as num?)?.toDouble(),
      collectionId: map['collectionId'] as String?,
      businessSubtotal: (map['businessSubtotal'] as num?)?.toDouble(),
      businessTaxAmount: (map['businessTaxAmount'] as num?)?.toDouble(),
      businessTotal: (map['businessTotal'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      tags: (map['tags'] as List<Object?>?)?.cast<String>() ?? const [],
      imagePath: map['imagePath'] as String?,
      originalImagePath: map['originalImagePath'] as String?,
      processedImagePath: map['processedImagePath'] as String?,
      imageProcessingStatus: map['imageProcessingStatus'] as String?,
      extractedText: map['extractedText'] as String?,
      fileUrl: map['fileUrl'] as String?,
      enrichment: receiptEnrichment,
      collectionEnrichment: collectionEnrichment,
      items: (map['items'] as List<dynamic>?)
              ?.map((i) => ReceiptItem.fromMap(
                  Map<String, Object?>.from(i as Map<dynamic, dynamic>)))
              .toList() ??
          const [],
      searchKeywords:
          (map['searchKeywords'] as List<dynamic>?)?.cast<String>() ?? const [],
      normalizedBrand: map['normalizedBrand'] as String?,
      metadata: map['metadata'] is Map
          ? Map<String, Object?>.from(map['metadata'] as Map)
          : null,
    );
  }

  /// Recommended: construct directly from Firestore docs
  factory Receipt.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError("Missing data for receipt ID: ${doc.id}");
    }

    final rawMetadata = data['metadata'];
    final Map<String, Object?>? metadata = rawMetadata is Map
        ? rawMetadata.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : null;

    final rawEnrichment = data['enrichment'];
    final ReceiptEnrichment? enrichment = rawEnrichment is Map
        ? ReceiptEnrichment.fromMap(
            rawEnrichment is Map<String, dynamic>
                ? Map<String, Object?>.from(rawEnrichment)
                : Map<String, Object?>.from(
                    rawEnrichment,
                  ),
          )
        : null;
    final rawCollectionEnrichment = data['collectionEnrichment'];
    final ReceiptCollectionEnrichment? collectionEnrichment =
        rawCollectionEnrichment is Map
            ? ReceiptCollectionEnrichment.fromMap(
                Map<String, Object?>.from(rawCollectionEnrichment),
              )
            : null;

    return Receipt(
      id: doc.id,
      storeName: data['storeName'] as String? ?? "Unknown Store",
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] as String? ?? "AUD",
      receiptType: data['receiptType'] as String? ?? 'personal',
      receiptTaxAmount: (data['receiptTaxAmount'] as num?)?.toDouble(),
      collectionId: data['collectionId'] as String?,
      businessSubtotal: (data['businessSubtotal'] as num?)?.toDouble(),
      businessTaxAmount: (data['businessTaxAmount'] as num?)?.toDouble(),
      businessTotal: (data['businessTotal'] as num?)?.toDouble(),
      notes: data['notes'] as String?,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      imagePath: data['imagePath'] as String?,
      originalImagePath: data['originalImagePath'] as String?,
      processedImagePath: data['processedImagePath'] as String?,
      imageProcessingStatus: data['imageProcessingStatus'] as String?,
      extractedText: data['extractedText'] as String?,
      fileUrl: data['fileUrl'] as String?,
      enrichment: enrichment,
      collectionEnrichment: collectionEnrichment,
      items: (data['items'] as List<dynamic>?)
              ?.map((i) => ReceiptItem.fromMap(
                  Map<String, Object?>.from(i as Map<dynamic, dynamic>)))
              .toList() ??
          const [],
      searchKeywords:
          (data['searchKeywords'] as List<dynamic>?)?.cast<String>() ??
              const [],
      normalizedBrand: data['normalizedBrand'] as String?,
      metadata: metadata,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeName,
        date,
        total,
        currency,
        receiptType,
        receiptTaxAmount,
        collectionId,
        businessSubtotal,
        businessTaxAmount,
        businessTotal,
        notes,
        tags,
        imagePath,
        originalImagePath,
        processedImagePath,
        imageProcessingStatus,
        extractedText,
        fileUrl,
        enrichment,
        collectionEnrichment,
        items,
        searchKeywords,
        normalizedBrand,
        metadata,
      ];
}

@immutable
class ReceiptEnrichment extends Equatable {
  final String? status;
  final int? retryCount;
  final int? version;
  final DateTime? enrichedAt;

  const ReceiptEnrichment({
    this.status,
    this.retryCount,
    this.version,
    this.enrichedAt,
  });

  factory ReceiptEnrichment.fromMap(Map<String, Object?> map) {
    final Object? enrichedAt = map['enrichedAt'];
    final DateTime? parsedEnrichedAt = enrichedAt is Timestamp
        ? enrichedAt.toDate()
        : enrichedAt is String
            ? DateTime.tryParse(enrichedAt)
            : enrichedAt is DateTime
                ? enrichedAt
                : null;

    return ReceiptEnrichment(
      status: map['status'] as String?,
      retryCount: (map['retryCount'] as num?)?.toInt(),
      version: (map['version'] as num?)?.toInt(),
      enrichedAt: parsedEnrichedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'status': status,
      'retryCount': retryCount,
      'version': version,
      'enrichedAt': enrichedAt == null ? null : Timestamp.fromDate(enrichedAt!),
    };
  }

  @override
  List<Object?> get props => [status, retryCount, version, enrichedAt];
}

@immutable
class ReceiptCollectionEnrichment extends Equatable {
  final String? status;
  final int? version;
  final DateTime? enrichedAt;
  final String? collectionId;

  const ReceiptCollectionEnrichment({
    this.status,
    this.version,
    this.enrichedAt,
    this.collectionId,
  });

  factory ReceiptCollectionEnrichment.fromMap(Map<String, Object?> map) {
    final Object? enrichedAt = map['enrichedAt'];
    final DateTime? parsedEnrichedAt = enrichedAt is Timestamp
        ? enrichedAt.toDate()
        : enrichedAt is String
            ? DateTime.tryParse(enrichedAt)
            : enrichedAt is DateTime
                ? enrichedAt
                : null;

    return ReceiptCollectionEnrichment(
      status: map['status'] as String?,
      version: (map['version'] as num?)?.toInt(),
      enrichedAt: parsedEnrichedAt,
      collectionId: map['collectionId'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'status': status,
      'version': version,
      'enrichedAt': enrichedAt == null ? null : Timestamp.fromDate(enrichedAt!),
      'collectionId': collectionId,
    };
  }

  @override
  List<Object?> get props => [
        status,
        version,
        enrichedAt,
        collectionId,
      ];
}
