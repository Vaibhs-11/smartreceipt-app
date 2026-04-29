import 'package:meta/meta.dart';

@immutable
class InsightsQuery {
  const InsightsQuery({
    this.startDate,
    this.endDate,
    this.collectionId,
    this.taxOnly = false,
    this.currency,
    this.categories,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final String? collectionId;
  final bool taxOnly;
  final String? currency;
  final List<String>? categories;

  bool get isCollectionQuery {
    final collectionId = this.collectionId;
    return collectionId != null && collectionId.trim().isNotEmpty;
  }

  bool get isEmpty =>
      startDate == null &&
      endDate == null &&
      !taxOnly &&
      (collectionId == null || collectionId!.trim().isEmpty) &&
      (currency == null || currency!.trim().isEmpty) &&
      (categories == null || categories!.isEmpty);

  @override
  String toString() {
    return 'InsightsQuery('
        'startDate=$startDate, '
        'endDate=$endDate, '
        'collectionId=$collectionId, '
        'taxOnly=$taxOnly, '
        'currency=$currency, '
        'categories=$categories'
        ')';
  }
}
