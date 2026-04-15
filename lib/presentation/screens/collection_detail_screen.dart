import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/models/insights_query.dart';
import 'package:receiptnest/domain/models/insights_result.dart';
import 'package:receiptnest/domain/services/insights_engine.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/routes/app_routes.dart';
import 'package:receiptnest/presentation/screens/add_receipt_screen.dart';
import 'package:receiptnest/presentation/screens/create_collection_screen.dart';
import 'package:receiptnest/presentation/screens/collections_preview_screen.dart';
import 'package:receiptnest/presentation/utils/root_scaffold_messenger.dart';
import 'package:receiptnest/presentation/widgets/collection_receipt_assignment_sheet.dart';

class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
  });

  final String collectionId;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  static const InsightsEngine _insightsEngine = InsightsEngine();
  final Set<String> _selectedReceiptIds = <String>{};
  String? _selectedInsightsCurrency;

  bool get _isSelectingReceipts => _selectedReceiptIds.isNotEmpty;

  void _toggleReceiptSelection(String receiptId) {
    setState(() {
      if (_selectedReceiptIds.contains(receiptId)) {
        _selectedReceiptIds.remove(receiptId);
      } else {
        _selectedReceiptIds.add(receiptId);
      }
    });
  }

  void _clearReceiptSelection() {
    if (_selectedReceiptIds.isEmpty) {
      return;
    }
    setState(_selectedReceiptIds.clear);
  }

  void _openEditCollection(Collection collection) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateCollectionScreen(collection: collection),
      ),
    );
  }

  Future<void> _updateCollection(Collection collection) async {
    final userId = ref.read(userIdProvider);
    if (userId == null) {
      return;
    }

    final updateCollection = ref.read(updateCollectionUseCaseProvider);
    await updateCollection(
      userId,
      collection.copyWith(updatedAt: DateTime.now()),
    );
  }

  Future<void> _pickCollectionDate(
    Collection collection, {
    required bool isStartDate,
  }) async {
    final initialDate = isStartDate
        ? (collection.startDate ?? collection.endDate ?? DateTime.now())
        : (collection.endDate ?? collection.startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (!mounted || picked == null) {
      return;
    }

    DateTime? startDate = collection.startDate;
    DateTime? endDate = collection.endDate;

    if (isStartDate) {
      startDate = picked;
      if (endDate != null && endDate.isBefore(startDate)) {
        endDate = startDate;
      }
    } else {
      endDate = picked;
      if (startDate != null && endDate.isBefore(startDate)) {
        startDate = endDate;
      }
    }

    await _updateCollection(
      collection.copyWith(
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<void> _toggleCollectionStatus(Collection collection) async {
    final nextStatus = collection.status == CollectionStatus.completed
        ? CollectionStatus.active
        : CollectionStatus.completed;
    await _updateCollection(collection.copyWith(status: nextStatus));
  }

  void _startReceiptSelection(List<Receipt> receipts) {
    if (receipts.isEmpty) {
      return;
    }
    _toggleReceiptSelection(receipts.first.id);
  }

  Widget _buildSummaryCard(
    Collection collection,
    List<Receipt> receipts,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _collectionTypeLabel(collection.type),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              _buildDateSection(collection),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                '${receipts.length} receipts',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _buildCurrencyTotals(receipts),
              const SizedBox(height: 16),
              _buildCompletionButton(collection),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSection(Collection collection) {
    final formatter = DateFormat.MMMd();

    if (collection.startDate == null && collection.endDate == null) {
      return InkWell(
        onTap: () => _pickCollectionDate(collection, isStartDate: true),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '+ Add dates',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
      );
    }

    if (collection.startDate != null && collection.endDate == null) {
      return InkWell(
        onTap: () => _pickCollectionDate(collection, isStartDate: false),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${formatter.format(collection.startDate!)} – Ongoing',
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      );
    }

    if (collection.startDate == null && collection.endDate != null) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          InkWell(
            onTap: () => _pickCollectionDate(collection, isStartDate: true),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '+ Add start date',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () => _pickCollectionDate(collection, isStartDate: false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                formatter.format(collection.endDate!),
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        InkWell(
          onTap: () => _pickCollectionDate(collection, isStartDate: true),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              formatter.format(collection.startDate!),
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const Text(
          '–',
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
        InkWell(
          onTap: () => _pickCollectionDate(collection, isStartDate: false),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              formatter.format(collection.endDate!),
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyTotals(List<Receipt> receipts) {
    final formatter = NumberFormat('#,##0.00');
    final totalsByCurrency = <String, double>{};
    for (final receipt in receipts) {
      final currency = receipt.currency.trim().isEmpty
          ? 'Unknown'
          : receipt.currency.trim().toUpperCase();
      totalsByCurrency[currency] =
          (totalsByCurrency[currency] ?? 0) + receipt.total;
    }

    if (totalsByCurrency.isEmpty) {
      return const Text(
        'No spend recorded yet',
        style: TextStyle(
          fontSize: 15,
          color: AppColors.textSecondary,
        ),
      );
    }

    final entries = totalsByCurrency.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: i == 0 ? const Text('💰') : const SizedBox(),
                ),
                const SizedBox(width: 6),
                Text(
                  '${entries[i].key} ${formatter.format(entries[i].value)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                    color:
                        i == 0 ? AppColors.accentTeal : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCompletionButton(Collection collection) {
    final isCompleted = collection.status == CollectionStatus.completed;

    if (!isCompleted) {
      return FilledButton(
        onPressed: () => _toggleCollectionStatus(collection),
        child: const Text('Mark as Complete'),
      );
    }

    return Row(
      children: [
        const Expanded(
          child: Text(
            '✓ Completed',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => _toggleCollectionStatus(collection),
          child: const Text('Reopen'),
        ),
      ],
    );
  }

  Widget _buildInsightsSection(List<Receipt> receipts) {
    final insights = _insightsEngine.build(
      receipts: receipts,
      query: InsightsQuery(collectionId: widget.collectionId),
    );
    final primaryCurrency = _getPrimaryInsightsCurrency(insights);
    final selectedCurrency = _resolveSelectedInsightsCurrency(
      insights,
      primaryCurrency,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'Spending Breakdown',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                  ),
                  if (insights.currencies.length > 1 &&
                      selectedCurrency != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _buildInsightsCurrencyTabs(
                        insights: insights,
                        selectedCurrency: selectedCurrency,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (insights.isEmpty)
                const _InsightsEmptyState()
              else
                _buildSelectedCurrencyInsights(
                  insights: insights,
                  selectedCurrency: selectedCurrency,
                  receipts: receipts,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsCurrencyTabs({
    required InsightsResult insights,
    required String selectedCurrency,
  }) {
    final effectiveSelectedCurrency = insights.currencies.any(
      (currency) => currency.currency == selectedCurrency,
    )
        ? selectedCurrency
        : insights.currencies.first.currency;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final currencyInsights in insights.currencies)
            _buildInsightsCurrencyTab(
              currency: currencyInsights.currency,
              isSelected:
                  currencyInsights.currency == effectiveSelectedCurrency,
            ),
        ],
      ),
    );
  }

  Widget _buildInsightsCurrencyTab({
    required String currency,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedInsightsCurrency = currency;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryNavy.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryNavy.withValues(alpha: 0.28)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                const Icon(
                  Icons.check,
                  size: 14,
                  color: AppColors.primaryNavy,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                currency,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? AppColors.primaryNavy
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCurrencyInsights({
    required InsightsResult insights,
    required String? selectedCurrency,
    required List<Receipt> receipts,
  }) {
    if (selectedCurrency == null) {
      return const _InsightsEmptyState();
    }

    final currencyInsights = insights.currencies
        .cast<CurrencyInsights?>()
        .firstWhere(
          (currency) => currency?.currency == selectedCurrency,
          orElse: () =>
              insights.currencies.isNotEmpty ? insights.currencies.first : null,
        );

    if (currencyInsights == null) {
      return const _InsightsEmptyState();
    }

    final topCategories = _buildDisplayCategories(currencyInsights.categories);
    if (topCategories.isEmpty) {
      return const _InsightsEmptyState();
    }

    return _buildCurrencyInsightChartSection(
      currency: currencyInsights.currency,
      categories: topCategories,
      receipts: receipts,
    );
  }

  String? _getPrimaryInsightsCurrency(InsightsResult insights) {
    if (insights.currencies.isEmpty) {
      return null;
    }

    final sortedCurrencies = insights.currencies.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return sortedCurrencies.first.currency;
  }

  String? _resolveSelectedInsightsCurrency(
    InsightsResult insights,
    String? primaryCurrency,
  ) {
    final selectedCurrency = _selectedInsightsCurrency;
    if (selectedCurrency != null &&
        insights.currencies
            .any((currency) => currency.currency == selectedCurrency)) {
      return selectedCurrency;
    }
    return primaryCurrency;
  }

  Widget _buildCurrencyInsightChartSection({
    required String currency,
    required List<_DisplayedCategoryInsight> categories,
    required List<Receipt> receipts,
  }) {
    final legendItems = <_InsightLegendItem>[
      for (var index = 0; index < categories.length; index++)
        _InsightLegendItem(
          category: categories[index],
          color: _insightPalette[index % _insightPalette.length],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Center(
          child: SizedBox(
            height: 164,
            width: 164,
            child: _buildPieChartOrFallback(
              currency: currency,
              legendItems: legendItems,
              receipts: receipts,
            ),
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < legendItems.length; index++) ...[
          _buildCategoryInsightRow(
            currency: currency,
            item: legendItems[index],
            receipts: receipts,
          ),
          if (index < legendItems.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildPieChartOrFallback({
    required String currency,
    required List<_InsightLegendItem> legendItems,
    required List<Receipt> receipts,
  }) {
    try {
      return PieChart(
        PieChartData(
          centerSpaceRadius: 40,
          sectionsSpace: 2,
          startDegreeOffset: -90,
          pieTouchData: PieTouchData(
            enabled: true,
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent) {
                return;
              }
              final touchedSection = response?.touchedSection;
              if (touchedSection == null) {
                return;
              }
              final index = touchedSection.touchedSectionIndex;
              if (index < 0 || index >= legendItems.length) {
                return;
              }
              _showCategoryDrilldownSheet(
                item: legendItems[index],
                currency: currency,
                receipts: receipts,
              );
            },
          ),
          sections: [
            for (final item in legendItems)
              PieChartSectionData(
                color: item.color,
                value: item.category.insight.totalAmount,
                title: '',
                radius: 24,
              ),
          ],
        ),
        duration: const Duration(milliseconds: 250),
      );
    } catch (_) {
      final amountFormatter = NumberFormat('#,##0.00');
      return Center(
        child: Text(
          '$currency ${amountFormatter.format(legendItems.fold<double>(
            0,
            (sum, item) => sum + item.category.insight.totalAmount,
          ))}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.accentTeal,
          ),
        ),
      );
    }
  }

  Widget _buildCategoryInsightRow({
    required String currency,
    required _InsightLegendItem item,
    required List<Receipt> receipts,
  }) {
    final amountFormatter = NumberFormat('#,##0.00');
    final percentageFormatter = NumberFormat.decimalPercentPattern(
      decimalDigits: 0,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCategoryDrilldownSheet(
          item: item,
          currency: currency,
          receipts: receipts,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.category.insight.category,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$currency '
                    '${amountFormatter.format(item.category.insight.totalAmount)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentTeal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${percentageFormatter.format(item.category.insight.percentage)} of spend',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCategoryDrilldownSheet({
    required _InsightLegendItem item,
    required String currency,
    required List<Receipt> receipts,
  }) async {
    final drilldown = _buildCategoryDrilldownData(
      receipts: receipts,
      currency: currency,
      displayedCategory: item.category,
      color: item.color,
    );

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDrilldownHeader(drilldown),
                  const SizedBox(height: 16),
                  _buildDrilldownSummary(drilldown),
                  const SizedBox(height: 16),
                  Expanded(
                    child: drilldown.receipts.isEmpty
                        ? const _CategoryDrilldownEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: drilldown.receipts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final receipt = drilldown.receipts[index];
                              return _buildDrilldownReceiptCard(
                                currency: currency,
                                receipt: receipt,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrilldownHeader(_CategoryDrilldownData drilldown) {
    final amountFormatter = NumberFormat('#,##0.00');
    final percentageFormatter = NumberFormat.decimalPercentPattern(
      decimalDigits: 0,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: drilldown.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                drilldown.category,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${drilldown.currency} '
                '${amountFormatter.format(drilldown.totalAmount)} '
                '(${percentageFormatter.format(drilldown.percentage)})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDrilldownSummary(_CategoryDrilldownData drilldown) {
    return Row(
      children: [
        Expanded(
          child: _buildDrilldownStat(
            value: '${drilldown.receiptCount}',
            label: 'Receipts',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDrilldownStat(
            value: '${drilldown.itemCount}',
            label: 'Items',
          ),
        ),
      ],
    );
  }

  Widget _buildDrilldownStat({
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrilldownReceiptCard({
    required String currency,
    required _ReceiptCategoryContribution receipt,
  }) {
    final amountFormatter = NumberFormat('#,##0.00');

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receipt.merchant,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.yMMMd().format(receipt.receiptDate),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$currency ${amountFormatter.format(receipt.totalAmount)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentTeal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < receipt.items.length; index++) ...[
              _buildDrilldownItemRow(
                currency: currency,
                item: receipt.items[index],
              ),
              if (index < receipt.items.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrilldownItemRow({
    required String currency,
    required _CategoryItemDetail item,
  }) {
    final amountFormatter = NumberFormat('#,##0.00');

    return Row(
      children: [
        Expanded(
          child: Text(
            item.name,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$currency ${amountFormatter.format(item.amount)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  _CategoryDrilldownData _buildCategoryDrilldownData({
    required List<Receipt> receipts,
    required String currency,
    required _DisplayedCategoryInsight displayedCategory,
    required Color color,
  }) {
    final contributions = <_ReceiptCategoryContribution>[];
    var itemCount = 0;

    for (final receipt in receipts) {
      final receiptCurrency = _normalizeCurrency(receipt.currency);
      if (receiptCurrency != currency) {
        continue;
      }

      final matchingItems = <_CategoryItemDetail>[];
      for (final item in receipt.items) {
        final amount = item.price;
        if (amount == null || amount <= 0) {
          continue;
        }

        final itemCategory = _resolveCollectionInsightCategory(item);
        if (!displayedCategory.categories.contains(itemCategory)) {
          continue;
        }

        matchingItems.add(
          _CategoryItemDetail(
            name: _resolveItemName(item),
            amount: amount,
          ),
        );
      }

      if (matchingItems.isEmpty) {
        continue;
      }

      matchingItems.sort((a, b) => b.amount.compareTo(a.amount));
      final totalAmount = matchingItems.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      );
      itemCount += matchingItems.length;

      contributions.add(
        _ReceiptCategoryContribution(
          receiptId: receipt.id,
          merchant: _resolveMerchant(receipt),
          receiptDate: receipt.date,
          totalAmount: totalAmount,
          items: matchingItems,
        ),
      );
    }

    contributions.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return _CategoryDrilldownData(
      category: displayedCategory.insight.category,
      currency: currency,
      totalAmount: displayedCategory.insight.totalAmount,
      percentage: displayedCategory.insight.percentage,
      color: color,
      receiptCount: contributions.length,
      itemCount: itemCount,
      receipts: contributions,
    );
  }

  String _resolveCollectionInsightCategory(ReceiptItem item) {
    final category = (item.collectionCategory ?? item.category)?.trim();
    if (category == null || category.isEmpty) {
      return InsightsEngine.fallbackCategory;
    }
    return category;
  }

  String _resolveItemName(ReceiptItem item) {
    final name = item.name.trim();
    if (name.isEmpty) {
      return 'Unnamed item';
    }
    return name;
  }

  String _resolveMerchant(Receipt receipt) {
    final merchant = receipt.storeName.trim();
    if (merchant.isEmpty) {
      return InsightsEngine.fallbackMerchant;
    }
    return merchant;
  }

  String _normalizeCurrency(String currency) {
    final normalized = currency.trim();
    if (normalized.isEmpty) {
      return InsightsEngine.fallbackCurrency;
    }
    return normalized;
  }

  List<_DisplayedCategoryInsight> _buildDisplayCategories(
    List<CategoryInsight> categories,
  ) {
    if (categories.length <= 5) {
      return categories
          .take(5)
          .map(
            (category) => _DisplayedCategoryInsight(
              insight: category,
              categories: <String>{category.category},
            ),
          )
          .toList();
    }

    final topCategories = categories.take(4).toList();
    final remaining = categories.skip(4).toList();
    final remainingTotal = remaining.fold<double>(
      0,
      (sum, category) => sum + category.totalAmount,
    );
    final remainingPercentage = remaining.fold<double>(
      0,
      (sum, category) => sum + category.percentage,
    );
    final remainingReceiptIds = <String>{};

    for (final category in remaining) {
      for (final contribution in category.receiptContributions) {
        remainingReceiptIds.add(contribution.receiptId);
      }
    }

    topCategories.add(
      CategoryInsight(
        category: 'Others',
        totalAmount: remainingTotal,
        percentage: remainingPercentage,
        receiptCount: remainingReceiptIds.length,
        receiptContributions: const <ReceiptContribution>[],
      ),
    );

    return [
      for (final category in topCategories.take(4))
        _DisplayedCategoryInsight(
          insight: category,
          categories: <String>{category.category},
        ),
      _DisplayedCategoryInsight(
        insight: topCategories.last,
        categories: remaining.map((category) => category.category).toSet(),
      ),
    ];
  }

  Future<String?> _pickCollectionId({
    String? excludeCollectionId,
    String title = 'Move to another Trip / Event',
  }) async {
    while (true) {
      final action = await showCollectionPickerBottomSheet(
        context,
        excludeCollectionId: excludeCollectionId,
        title: title,
      );

      if (!mounted || action == null) {
        return null;
      }

      if (action.type == CollectionPickerActionType.createNew) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => const CreateCollectionScreen(),
          ),
        );
        ref.refresh(collectionsProvider);
        ref.refresh(collectionsStreamProvider);

        final collections = await ref.read(collectionsProvider.future);
        if (!mounted) {
          return null;
        }

        final hasSelectableCollection = collections.any(
          (collection) => collection.id != excludeCollectionId,
        );
        if (!hasSelectableCollection) {
          return null;
        }
        continue;
      }

      return action.collectionId;
    }
  }

  Future<void> _showAddReceiptSheet() async {
    if (!ref.read(premiumCollectionAccessProvider)) {
      await _showUpgradePrompt();
      return;
    }

    final action = await showModalBottomSheet<_AddReceiptAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Add new receipt'),
                onTap: () =>
                    Navigator.of(context).pop(_AddReceiptAction.addNew),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_outlined),
                title: const Text('Add existing receipts'),
                onTap: () =>
                    Navigator.of(context).pop(_AddReceiptAction.addExisting),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == _AddReceiptAction.addNew) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AddReceiptScreen(
            initialCollectionId: widget.collectionId,
          ),
        ),
      );
      return;
    }

    final receipts = await ref.read(receiptsProvider.future);
    if (!mounted) {
      return;
    }

    final availableReceipts = receipts
        .where((receipt) => receipt.id.isNotEmpty)
        .where((receipt) => receipt.collectionId != widget.collectionId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final selectedIds = await showReceiptSelectionBottomSheet(
      context,
      receipts: availableReceipts,
      title: 'Add receipts to Trip / Event',
      ctaLabel: 'Add to Trip / Event',
    );

    if (!mounted || selectedIds == null || selectedIds.isEmpty) {
      return;
    }

    if (!ref.read(premiumCollectionAccessProvider)) {
      await _showUpgradePrompt();
      return;
    }

    await ref
        .read(receiptRepositoryProviderOverride)
        .assignReceiptsToCollection(selectedIds, widget.collectionId);
    ref.read(receiptCollectionOverridesProvider.notifier).state = {
      ...ref.read(receiptCollectionOverridesProvider),
      for (final receiptId in selectedIds) receiptId: widget.collectionId,
    };

    showRootSnackBar(
      const SnackBar(content: Text('Receipts added to Trip / Event')),
    );
  }

  Future<void> _showSelectionActions() async {
    if (_selectedReceiptIds.isEmpty) {
      return;
    }

    if (!ref.read(premiumCollectionAccessProvider)) {
      await _showUpgradePrompt();
      return;
    }

    final action = await showModalBottomSheet<_SelectedReceiptAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Remove from Trip / Event'),
                onTap: () => Navigator.of(context)
                    .pop(_SelectedReceiptAction.removeFromCollection),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('Move to another Trip / Event'),
                onTap: () =>
                    Navigator.of(context).pop(_SelectedReceiptAction.move),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete'),
                onTap: () =>
                    Navigator.of(context).pop(_SelectedReceiptAction.delete),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    final repository = ref.read(receiptRepositoryProviderOverride);
    final selectedIds = _selectedReceiptIds.toList();

    switch (action) {
      case _SelectedReceiptAction.removeFromCollection:
        await repository.removeReceiptsFromCollection(selectedIds);
        ref.read(receiptCollectionOverridesProvider.notifier).state = {
          ...ref.read(receiptCollectionOverridesProvider),
          for (final receiptId in selectedIds) receiptId: null,
        };
        _clearReceiptSelection();
        showRootSnackBar(
          const SnackBar(content: Text('Removed from Trip / Event')),
        );
        return;
      case _SelectedReceiptAction.move:
        final newCollectionId = await _pickCollectionId(
          excludeCollectionId: widget.collectionId,
        );
        if (!mounted || newCollectionId == null) {
          return;
        }
        await repository.assignReceiptsToCollection(
          selectedIds,
          newCollectionId,
        );
        ref.read(receiptCollectionOverridesProvider.notifier).state = {
          ...ref.read(receiptCollectionOverridesProvider),
          for (final receiptId in selectedIds) receiptId: newCollectionId,
        };
        _clearReceiptSelection();
        showRootSnackBar(
          const SnackBar(content: Text('Moved to another Trip / Event')),
        );
        return;
      case _SelectedReceiptAction.delete:
        final shouldDelete = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete selected receipts?'),
                content: const Text(
                  'This action cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!shouldDelete) {
          return;
        }
        for (final receiptId in selectedIds) {
          await repository.deleteReceipt(receiptId);
        }
        _clearReceiptSelection();
        showRootSnackBar(
          const SnackBar(content: Text('Receipts deleted')),
        );
        return;
    }
  }

  void _handleReceiptTap(Receipt receipt) {
    if (_isSelectingReceipts) {
      _toggleReceiptSelection(receipt.id);
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.receiptDetail,
      arguments: receipt.id,
    );
  }

  Future<void> _showUpgradePrompt() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const CollectionsPreviewScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAccess = ref.watch(premiumCollectionAccessProvider);
    final collectionAsync =
        ref.watch(collectionStreamProvider(widget.collectionId));
    final receiptsAsync =
        ref.watch(collectionReceiptsStreamProvider(widget.collectionId));

    return Scaffold(
      appBar: AppBar(
        title: collectionAsync.maybeWhen(
          data: (collection) => Text(
            _isSelectingReceipts
                ? '${_selectedReceiptIds.length} selected'
                : collection?.name ?? 'Collection',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
          orElse: () => const Text(
            'Collection',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
        actions: [
          if (_isSelectingReceipts)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear selection',
              onPressed: _clearReceiptSelection,
            )
          else
            collectionAsync.maybeWhen(
              data: (collection) {
                if (collection == null || !hasAccess) {
                  return const SizedBox.shrink();
                }

                return IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit collection',
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CreateCollectionScreen(collection: collection),
                      ),
                    );
                  },
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
        ],
      ),
      body: SafeArea(
        child: !hasAccess
            ? const _CollectionAccessDenied()
            : collectionAsync.when(
                data: (collection) {
                  if (collection == null) {
                    return const Center(
                      child: Text('Collection not found.'),
                    );
                  }

                  return receiptsAsync.when(
                    data: (receipts) {
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 96),
                        children: [
                          _buildSummaryCard(collection, receipts),
                          _buildInsightsSection(receipts),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Receipts',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryNavy,
                                    ),
                                  ),
                                ),
                                if (!_isSelectingReceipts)
                                  TextButton(
                                    onPressed: () =>
                                        _startReceiptSelection(receipts),
                                    child: const Text('Select'),
                                  ),
                              ],
                            ),
                          ),
                          if (receipts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                              child: Center(
                                child: Text(
                                  'No receipts in this collection yet',
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                0,
                              ),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: receipts.length,
                              itemBuilder: (context, index) {
                                final receipt = receipts[index];
                                final isSelected = _selectedReceiptIds.contains(
                                  receipt.id,
                                );

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isSelected
                                            ? AppColors.primaryNavy
                                                .withValues(alpha: 0.25)
                                            : Colors.grey.shade200,
                                      ),
                                    ),
                                    color: isSelected
                                        ? AppColors.primaryNavy
                                            .withValues(alpha: 0.06)
                                        : Colors.white,
                                    child: ListTile(
                                      onTap: () => _handleReceiptTap(receipt),
                                      onLongPress: () =>
                                          _toggleReceiptSelection(
                                        receipt.id,
                                      ),
                                      leading: _isSelectingReceipts
                                          ? Icon(
                                              isSelected
                                                  ? Icons.check_circle
                                                  : Icons
                                                      .radio_button_unchecked,
                                              color: isSelected
                                                  ? AppColors.primaryNavy
                                                  : AppColors.textSecondary,
                                            )
                                          : null,
                                      title: Text(
                                        receipt.storeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        DateFormat.yMMMd().format(receipt.date),
                                      ),
                                      trailing: Text(
                                        '${receipt.currency} ${receipt.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: AppColors.accentTeal,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 88),
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Text('Failed to load receipts: $error'),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text('Failed to load collection: $error'),
                ),
              ),
      ),
      floatingActionButton: hasAccess && !_isSelectingReceipts
          ? FloatingActionButton.extended(
              onPressed: _showAddReceiptSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add Receipt'),
            )
          : null,
      bottomNavigationBar: _isSelectingReceipts
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _showSelectionActions,
                icon: const Icon(Icons.more_horiz),
                label: const Text('Manage selected receipts'),
              ),
            )
          : null,
    );
  }
}

const List<Color> _insightPalette = <Color>[
  AppColors.primaryNavy,
  AppColors.accentTeal,
  AppColors.lightTeal,
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
];

class _InsightLegendItem {
  const _InsightLegendItem({
    required this.category,
    required this.color,
  });

  final _DisplayedCategoryInsight category;
  final Color color;
}

class _DisplayedCategoryInsight {
  const _DisplayedCategoryInsight({
    required this.insight,
    required this.categories,
  });

  final CategoryInsight insight;
  final Set<String> categories;
}

class _CategoryDrilldownData {
  const _CategoryDrilldownData({
    required this.category,
    required this.currency,
    required this.totalAmount,
    required this.percentage,
    required this.color,
    required this.receiptCount,
    required this.itemCount,
    required this.receipts,
  });

  final String category;
  final String currency;
  final double totalAmount;
  final double percentage;
  final Color color;
  final int receiptCount;
  final int itemCount;
  final List<_ReceiptCategoryContribution> receipts;
}

class _ReceiptCategoryContribution {
  const _ReceiptCategoryContribution({
    required this.receiptId,
    required this.merchant,
    required this.receiptDate,
    required this.totalAmount,
    required this.items,
  });

  final String receiptId;
  final String merchant;
  final DateTime receiptDate;
  final double totalAmount;
  final List<_CategoryItemDetail> items;
}

class _CategoryItemDetail {
  const _CategoryItemDetail({
    required this.name,
    required this.amount,
  });

  final String name;
  final double amount;
}

class _InsightsEmptyState extends StatelessWidget {
  const _InsightsEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pie_chart_outline_rounded,
              size: 28,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 8),
            Text(
              'No insights yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Add receipts to see spending breakdown',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDrilldownEmptyState extends StatelessWidget {
  const _CategoryDrilldownEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No matching items found for this category.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

enum _AddReceiptAction { addNew, addExisting }

enum _SelectedReceiptAction { removeFromCollection, move, delete }

class _CollectionAccessDenied extends StatelessWidget {
  const _CollectionAccessDenied();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Trips & Events are available on an active trial or subscription.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryNavy,
          ),
        ),
      ),
    );
  }
}

String _collectionTypeLabel(CollectionType type) {
  return type == CollectionType.work ? 'Work' : 'Personal';
}
