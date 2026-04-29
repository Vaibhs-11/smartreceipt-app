import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

DateTime _currentCollectionDateTime() => DateTime.now();

enum CollectionType { personal, work }

extension CollectionTypeX on CollectionType {
  String get asString {
    switch (this) {
      case CollectionType.personal:
        return 'personal';
      case CollectionType.work:
        return 'work';
    }
  }

  static CollectionType fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'work':
        return CollectionType.work;
      case 'personal':
      default:
        return CollectionType.personal;
    }
  }
}

enum CollectionStatus { active, completed }

extension CollectionStatusX on CollectionStatus {
  String get asString {
    switch (this) {
      case CollectionStatus.active:
        return 'active';
      case CollectionStatus.completed:
        return 'completed';
    }
  }

  static CollectionStatus fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return CollectionStatus.completed;
      case 'active':
      default:
        return CollectionStatus.active;
    }
  }
}

DateTime? _parseDateTime(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is Timestamp) {
    return raw.toDate();
  }
  if (raw is DateTime) {
    return raw;
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  if (raw is double) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  return null;
}

@immutable
class Collection extends Equatable {
  const Collection({
    required this.id,
    required this.name,
    this.type = CollectionType.personal,
    this.startDate,
    this.endDate,
    this.notes,
    this.status = CollectionStatus.active,
    required this.createdAt,
    required this.updatedAt,
    this.totalAmount,
    this.receiptCount,
    this.lastExportedAt,
  });

  final String id;
  final String name;
  final CollectionType type;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;
  final CollectionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? totalAmount;
  final int? receiptCount;
  final DateTime? lastExportedAt;

  Collection copyWith({
    String? id,
    String? name,
    CollectionType? type,
    DateTime? startDate,
    DateTime? endDate,
    String? notes,
    CollectionStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? totalAmount,
    int? receiptCount,
    DateTime? lastExportedAt,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalAmount: totalAmount ?? this.totalAmount,
      receiptCount: receiptCount ?? this.receiptCount,
      lastExportedAt: lastExportedAt ?? this.lastExportedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'type': type.asString,
      'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
      'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
      'notes': notes,
      'status': status.asString,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'totalAmount': totalAmount,
      'receiptCount': receiptCount,
      'lastExportedAt':
          lastExportedAt == null ? null : Timestamp.fromDate(lastExportedAt!),
    };
  }

  factory Collection.fromMap(Map<String, Object?> map, {String? id}) {
    final fallbackNow = _currentCollectionDateTime();

    return Collection(
      id: id ?? map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      type: CollectionTypeX.fromString(map['type'] as String?),
      startDate: _parseDateTime(map['startDate']),
      endDate: _parseDateTime(map['endDate']),
      notes: map['notes'] as String?,
      status: CollectionStatusX.fromString(map['status'] as String?),
      createdAt: _parseDateTime(map['createdAt']) ?? fallbackNow,
      updatedAt: _parseDateTime(map['updatedAt']) ?? fallbackNow,
      totalAmount: (map['totalAmount'] as num?)?.toDouble(),
      receiptCount: (map['receiptCount'] as num?)?.toInt(),
      lastExportedAt: _parseDateTime(map['lastExportedAt']),
    );
  }

  factory Collection.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Collection.fromMap(data, id: doc.id);
  }

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        startDate,
        endDate,
        notes,
        status,
        createdAt,
        updatedAt,
        totalAmount,
        receiptCount,
        lastExportedAt,
      ];
}
