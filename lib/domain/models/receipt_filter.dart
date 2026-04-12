import 'package:meta/meta.dart';

@immutable
class ReceiptFilter {
  const ReceiptFilter({
    this.startDate,
    this.endDate,
    this.collectionId,
    this.taxClaimableOnly,
    this.categories,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final String? collectionId;
  final bool? taxClaimableOnly;
  final List<String>? categories;

  bool get isEmpty =>
      startDate == null &&
      endDate == null &&
      collectionId == null &&
      taxClaimableOnly == null &&
      (categories == null || categories!.isEmpty);

  @override
  String toString() {
    return 'ReceiptFilter('
        'startDate=$startDate, '
        'endDate=$endDate, '
        'collectionId=$collectionId, '
        'taxClaimableOnly=$taxClaimableOnly, '
        'categories=$categories'
        ')';
  }
}
