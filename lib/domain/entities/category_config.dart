import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryConfig {
  const CategoryConfig({
    this.categories = const <String>[],
    this.version,
    this.updatedAt,
  });

  final List<String> categories;
  final int? version;
  final DateTime? updatedAt;

  factory CategoryConfig.fromFirestore(Map<String, dynamic> data) {
    final rawCategories = data['categories'];
    return CategoryConfig(
      categories: rawCategories is List<dynamic>
          ? rawCategories.whereType<String>().toList()
          : const <String>[],
      version: (data['version'] as num?)?.toInt(),
      updatedAt: _parseUpdatedAt(data['updatedAt']),
    );
  }

  static DateTime? _parseUpdatedAt(Object? rawUpdatedAt) {
    if (rawUpdatedAt is Timestamp) {
      return rawUpdatedAt.toDate();
    }
    if (rawUpdatedAt is String) {
      return DateTime.tryParse(rawUpdatedAt);
    }
    if (rawUpdatedAt is DateTime) {
      return rawUpdatedAt;
    }
    return null;
  }
}
