import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

DateTime _currentTripDateTime() => DateTime.now();

enum TripType { personal, work }

extension TripTypeX on TripType {
  String get asString {
    switch (this) {
      case TripType.personal:
        return 'personal';
      case TripType.work:
        return 'work';
    }
  }

  static TripType fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'work':
        return TripType.work;
      case 'personal':
      default:
        return TripType.personal;
    }
  }
}

enum TripStatus { active, completed }

extension TripStatusX on TripStatus {
  String get asString {
    switch (this) {
      case TripStatus.active:
        return 'active';
      case TripStatus.completed:
        return 'completed';
    }
  }

  static TripStatus fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return TripStatus.completed;
      case 'active':
      default:
        return TripStatus.active;
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
class Trip extends Equatable {
  const Trip({
    required this.id,
    required this.name,
    this.type = TripType.personal,
    this.startDate,
    this.endDate,
    this.notes,
    this.status = TripStatus.active,
    required this.createdAt,
    required this.updatedAt,
    this.totalAmount,
    this.receiptCount,
    this.lastExportedAt,
  });

  final String id;
  final String name;
  final TripType type;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;
  final TripStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? totalAmount;
  final int? receiptCount;
  final DateTime? lastExportedAt;

  Trip copyWith({
    String? id,
    String? name,
    TripType? type,
    DateTime? startDate,
    DateTime? endDate,
    String? notes,
    TripStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? totalAmount,
    int? receiptCount,
    DateTime? lastExportedAt,
  }) {
    return Trip(
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

  factory Trip.fromMap(Map<String, Object?> map, {String? id}) {
    final fallbackNow = _currentTripDateTime();

    return Trip(
      id: id ?? map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      type: TripTypeX.fromString(map['type'] as String?),
      startDate: _parseDateTime(map['startDate']),
      endDate: _parseDateTime(map['endDate']),
      notes: map['notes'] as String?,
      status: TripStatusX.fromString(map['status'] as String?),
      createdAt: _parseDateTime(map['createdAt']) ?? fallbackNow,
      updatedAt: _parseDateTime(map['updatedAt']) ?? fallbackNow,
      totalAmount: (map['totalAmount'] as num?)?.toDouble(),
      receiptCount: (map['receiptCount'] as num?)?.toInt(),
      lastExportedAt: _parseDateTime(map['lastExportedAt']),
    );
  }

  factory Trip.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Trip.fromMap(data, id: doc.id);
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
