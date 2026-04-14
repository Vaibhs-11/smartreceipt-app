import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/models/insights_query.dart';
import 'package:receiptnest/domain/models/insights_result.dart';

class InsightsEngine {
  const InsightsEngine();

  static const String fallbackCategory = 'Misc';
  static const String fallbackMerchant = 'Unknown';
  static const String fallbackCurrency = 'Unknown';

  InsightsResult build({
    required List<Receipt> receipts,
    required InsightsQuery query,
  }) {
    final includedEntries = <_IncludedItemEntry>[];

    for (final receipt in receipts) {
      if (!_matchesReceipt(receipt, query)) {
        continue;
      }

      final merchant = _resolveMerchant(receipt);
      final currency = _resolveCurrency(receipt.currency);

      for (final item in receipt.items) {
        final amount = item.price;
        if (amount == null || amount <= 0) {
          continue;
        }
        if (query.taxOnly && !item.taxClaimable) {
          continue;
        }

        final category = _resolveCategory(item: item, query: query);
        if (!_matchesCategory(category, query.categories)) {
          continue;
        }

        includedEntries.add(
          _IncludedItemEntry(
            receiptId: receipt.id,
            merchant: merchant,
            receiptDate: receipt.date,
            currency: currency,
            category: category,
            amount: amount,
          ),
        );
      }
    }

    if (includedEntries.isEmpty) {
      return const InsightsResult(
        receiptCount: 0,
        itemCount: 0,
        currencies: <CurrencyInsights>[],
      );
    }

    final includedReceiptIds =
        includedEntries.map((entry) => entry.receiptId).toSet();

    final includedDates =
        includedEntries.map((entry) => entry.receiptDate).toList()..sort();

    final currencyBuckets = <String, List<_IncludedItemEntry>>{};
    for (final entry in includedEntries) {
      currencyBuckets
          .putIfAbsent(entry.currency, () => <_IncludedItemEntry>[])
          .add(entry);
    }

    final currencies = currencyBuckets.entries
        .map((entry) => _buildCurrencyInsights(entry.key, entry.value))
        .toList()
      ..sort((a, b) => a.currency.compareTo(b.currency));

    return InsightsResult(
      receiptCount: includedReceiptIds.length,
      itemCount: includedEntries.length,
      startDate: includedDates.first,
      endDate: includedDates.last,
      currencies: currencies,
    );
  }

  bool _matchesReceipt(Receipt receipt, InsightsQuery query) {
    final queryCollectionId = query.collectionId?.trim();
    if (queryCollectionId != null && queryCollectionId.isNotEmpty) {
      if (receipt.collectionId != queryCollectionId) {
        return false;
      }
    }

    final queryCurrency = query.currency?.trim();
    if (queryCurrency != null && queryCurrency.isNotEmpty) {
      final receiptCurrency = _resolveCurrency(receipt.currency);
      if (receiptCurrency != queryCurrency) {
        return false;
      }
    }

    final receiptDate = receipt.date;
    if (query.startDate != null && receiptDate.isBefore(query.startDate!)) {
      return false;
    }
    if (query.endDate != null && receiptDate.isAfter(query.endDate!)) {
      return false;
    }

    return true;
  }

  CurrencyInsights _buildCurrencyInsights(
    String currency,
    List<_IncludedItemEntry> entries,
  ) {
    final totalAmount = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.amount,
    );
    final receiptIds = entries.map((entry) => entry.receiptId).toSet();

    final categoryBuckets = <String, List<_IncludedItemEntry>>{};
    for (final entry in entries) {
      categoryBuckets
          .putIfAbsent(entry.category, () => <_IncludedItemEntry>[])
          .add(entry);
    }

    final categories = categoryBuckets.entries
        .map((entry) =>
            _buildCategoryInsight(entry.key, entry.value, totalAmount))
        .toList()
      ..sort((a, b) {
        final amountComparison = b.totalAmount.compareTo(a.totalAmount);
        if (amountComparison != 0) {
          return amountComparison;
        }
        return a.category.compareTo(b.category);
      });

    return CurrencyInsights(
      currency: currency,
      totalAmount: totalAmount,
      receiptCount: receiptIds.length,
      itemCount: entries.length,
      categories: categories,
    );
  }

  CategoryInsight _buildCategoryInsight(
    String category,
    List<_IncludedItemEntry> entries,
    double currencyTotalAmount,
  ) {
    final totalAmount = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.amount,
    );

    final receiptContributionMap = <String, _ContributionAccumulator>{};
    for (final entry in entries) {
      receiptContributionMap.update(
        entry.receiptId,
        (existing) => existing.copyWith(amount: existing.amount + entry.amount),
        ifAbsent: () => _ContributionAccumulator(
          receiptId: entry.receiptId,
          merchant: entry.merchant,
          receiptDate: entry.receiptDate,
          amount: entry.amount,
        ),
      );
    }

    final receiptContributions = receiptContributionMap.values
        .map(
          (contribution) => ReceiptContribution(
            receiptId: contribution.receiptId,
            merchant: contribution.merchant,
            receiptDate: contribution.receiptDate,
            amount: contribution.amount,
          ),
        )
        .toList()
      ..sort((a, b) {
        final amountComparison = b.amount.compareTo(a.amount);
        if (amountComparison != 0) {
          return amountComparison;
        }
        final dateComparison = b.receiptDate.compareTo(a.receiptDate);
        if (dateComparison != 0) {
          return dateComparison;
        }
        return a.receiptId.compareTo(b.receiptId);
      });

    return CategoryInsight(
      category: category,
      totalAmount: totalAmount,
      percentage:
          currencyTotalAmount > 0 ? totalAmount / currencyTotalAmount : 0,
      receiptCount: receiptContributionMap.length,
      receiptContributions: receiptContributions,
    );
  }

  String _resolveCategory({
    required ReceiptItem item,
    required InsightsQuery query,
  }) {
    final rawCategory = query.isCollectionQuery
        ? item.collectionCategory ?? item.category
        : item.category;

    final normalizedCategory = rawCategory?.trim();
    if (normalizedCategory == null || normalizedCategory.isEmpty) {
      return fallbackCategory;
    }
    return normalizedCategory;
  }

  bool _matchesCategory(String category, List<String>? selectedCategories) {
    if (selectedCategories == null || selectedCategories.isEmpty) {
      return true;
    }

    final normalizedSelected = selectedCategories
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (normalizedSelected.isEmpty) {
      return true;
    }

    return normalizedSelected.contains(category);
  }

  String _resolveMerchant(Receipt receipt) {
    final merchant = receipt.storeName.trim();
    if (merchant.isEmpty) {
      return fallbackMerchant;
    }
    return merchant;
  }

  String _resolveCurrency(String currency) {
    final normalizedCurrency = currency.trim();
    if (normalizedCurrency.isEmpty) {
      return fallbackCurrency;
    }
    return normalizedCurrency;
  }
}

class _IncludedItemEntry {
  const _IncludedItemEntry({
    required this.receiptId,
    required this.merchant,
    required this.receiptDate,
    required this.currency,
    required this.category,
    required this.amount,
  });

  final String receiptId;
  final String merchant;
  final DateTime receiptDate;
  final String currency;
  final String category;
  final double amount;
}

class _ContributionAccumulator {
  const _ContributionAccumulator({
    required this.receiptId,
    required this.merchant,
    required this.receiptDate,
    required this.amount,
  });

  final String receiptId;
  final String merchant;
  final DateTime receiptDate;
  final double amount;

  _ContributionAccumulator copyWith({double? amount}) {
    return _ContributionAccumulator(
      receiptId: receiptId,
      merchant: merchant,
      receiptDate: receiptDate,
      amount: amount ?? this.amount,
    );
  }
}
