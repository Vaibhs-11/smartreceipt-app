import 'package:meta/meta.dart';

@immutable
class ReceiptFilter {
  const ReceiptFilter({
    this.startDate,
    this.endDate,
    this.tripId,
    this.taxClaimableOnly,
    this.categories,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final String? tripId;
  final bool? taxClaimableOnly;
  final List<String>? categories;

  bool get isEmpty =>
      startDate == null &&
      endDate == null &&
      tripId == null &&
      taxClaimableOnly == null &&
      (categories == null || categories!.isEmpty);

  @override
  String toString() {
    return 'ReceiptFilter('
        'startDate=$startDate, '
        'endDate=$endDate, '
        'tripId=$tripId, '
        'taxClaimableOnly=$taxClaimableOnly, '
        'categories=$categories'
        ')';
  }
}
