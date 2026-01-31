import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReceiptSearchFilters {
  static const _unset = Object();

  const ReceiptSearchFilters({
    this.query = "",
    this.store,
    this.startDate,
    this.endDate,
    this.minTotal,
    this.maxTotal,
    this.taxClaimable,
  });

  final String query;
  final String? store;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? minTotal;
  final double? maxTotal;
  final bool? taxClaimable;

  ReceiptSearchFilters copyWith({
    String? query,
    Object? store = _unset,
    Object? startDate = _unset,
    Object? endDate = _unset,
    Object? minTotal = _unset,
    Object? maxTotal = _unset,
    Object? taxClaimable = _unset,
  }) {
    return ReceiptSearchFilters(
      query: query ?? this.query,
      store: identical(store, _unset) ? this.store : store as String?,
      startDate: identical(startDate, _unset)
          ? this.startDate
          : startDate as DateTime?,
      endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
      minTotal:
          identical(minTotal, _unset) ? this.minTotal : minTotal as double?,
      maxTotal:
          identical(maxTotal, _unset) ? this.maxTotal : maxTotal as double?,
      taxClaimable: identical(taxClaimable, _unset)
          ? this.taxClaimable
          : taxClaimable as bool?,
    );
  }

  ReceiptSearchFilters clearFilters() {
    return ReceiptSearchFilters(query: query);
  }

  bool get hasActiveFilters =>
      (store != null && store!.isNotEmpty) ||
      startDate != null ||
      endDate != null ||
      minTotal != null ||
      maxTotal != null ||
      taxClaimable != null;
}

final receiptSearchFiltersProvider =
    StateProvider<ReceiptSearchFilters>((ref) => const ReceiptSearchFilters());
