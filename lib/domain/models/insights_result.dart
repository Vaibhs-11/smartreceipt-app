import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
class ReceiptContribution extends Equatable {
  const ReceiptContribution({
    required this.receiptId,
    required this.merchant,
    required this.receiptDate,
    required this.amount,
  });

  final String receiptId;
  final String merchant;
  final DateTime receiptDate;
  final double amount;

  @override
  List<Object?> get props => [receiptId, merchant, receiptDate, amount];
}

@immutable
class CategoryInsight extends Equatable {
  const CategoryInsight({
    required this.category,
    required this.totalAmount,
    required this.percentage,
    required this.receiptCount,
    this.receiptContributions = const <ReceiptContribution>[],
  });

  final String category;
  final double totalAmount;
  final double percentage;
  final int receiptCount;
  final List<ReceiptContribution> receiptContributions;

  @override
  List<Object?> get props => [
        category,
        totalAmount,
        percentage,
        receiptCount,
        receiptContributions,
      ];
}

@immutable
class CurrencyInsights extends Equatable {
  const CurrencyInsights({
    required this.currency,
    required this.totalAmount,
    required this.receiptCount,
    required this.itemCount,
    this.categories = const <CategoryInsight>[],
  });

  final String currency;
  final double totalAmount;
  final int receiptCount;
  final int itemCount;
  final List<CategoryInsight> categories;

  @override
  List<Object?> get props => [
        currency,
        totalAmount,
        receiptCount,
        itemCount,
        categories,
      ];
}

@immutable
class InsightsResult extends Equatable {
  const InsightsResult({
    required this.receiptCount,
    required this.itemCount,
    required this.currencies,
    this.startDate,
    this.endDate,
  });

  final int receiptCount;
  final int itemCount;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<CurrencyInsights> currencies;

  bool get isEmpty => receiptCount == 0 && itemCount == 0 && currencies.isEmpty;

  @override
  List<Object?> get props => [
        receiptCount,
        itemCount,
        startDate,
        endDate,
        currencies,
      ];
}
