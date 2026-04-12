import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receiptnest/core/services/analytics_service.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/providers/receipt_search_filters_provider.dart';
import 'package:receiptnest/presentation/routes/app_routes.dart';
import 'package:receiptnest/presentation/screens/add_receipt_screen.dart';
import 'package:receiptnest/presentation/screens/collection_detail_screen.dart';
import 'package:receiptnest/presentation/screens/collections_list_screen.dart';
import 'package:receiptnest/presentation/screens/collections_preview_screen.dart';
import 'package:receiptnest/presentation/screens/create_collection_screen.dart';
import 'package:receiptnest/domain/models/categorised_item_view.dart';
import 'package:receiptnest/domain/utils/item_index_builder.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';
import 'package:receiptnest/presentation/utils/root_scaffold_messenger.dart';
import 'package:receiptnest/presentation/widgets/collection_receipt_assignment_sheet.dart';
import 'package:receiptnest/services/receipt_image_source_service.dart';

class PremiumReceiptHomeScreen extends ConsumerStatefulWidget {
  const PremiumReceiptHomeScreen({super.key});

  @override
  ConsumerState<PremiumReceiptHomeScreen> createState() =>
      _PremiumReceiptHomeScreenState();
}

class _PremiumReceiptHomeScreenState
    extends ConsumerState<PremiumReceiptHomeScreen> {
  late final TextEditingController _searchController;
  static const String _swipeHintPrefKey = 'receipt_swipe_hint_shown';
  static const List<_CategoryChipItem> _categoryChips = [
    _CategoryChipItem(label: 'All', icon: Icons.receipt_long),
    _CategoryChipItem(label: 'Food & Dining', icon: Icons.restaurant),
    _CategoryChipItem(label: 'Travel & Transport', icon: Icons.directions_car),
    _CategoryChipItem(
      label: 'Electronics & Appliances',
      icon: Icons.devices,
    ),
    _CategoryChipItem(label: 'Home & Household', icon: Icons.home),
    _CategoryChipItem(label: 'Fashion & Personal Care', icon: Icons.checkroom),
    _CategoryChipItem(label: 'Bills & Utilities', icon: Icons.receipt),
    _CategoryChipItem(label: 'Health & Medical', icon: Icons.local_hospital),
    _CategoryChipItem(label: 'Other', icon: Icons.category),
  ];
  bool _showSwipeHint = false;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  List<CategorisedItemView> _itemIndex = const [];
  final Set<String> _selectedReceiptIds = <String>{};
  bool _isCollectionsExpanded = true;

  bool get _isSelectingReceipts => _selectedReceiptIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initialFilters = ref.read(receiptSearchFiltersProvider);
    _searchController = TextEditingController(text: initialFilters.query);
    _loadSwipeHint();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSwipeHint() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_swipeHintPrefKey) ?? false;
    if (!mounted) return;
    setState(() => _showSwipeHint = !shown);
  }

  void _dismissSwipeHint() {
    if (!_showSwipeHint) return;
    setState(() => _showSwipeHint = false);
    _persistSwipeHintShown();
  }

  Future<void> _persistSwipeHintShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_swipeHintPrefKey, true);
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  Map<String, String?> _receiptDetailArguments(
    String receiptId, {
    String? highlightCategory,
    String? highlightItem,
  }) {
    return {
      'receiptId': receiptId,
      'highlightCategory': highlightCategory ??
          (_selectedCategory == 'All' ? null : _selectedCategory),
      'highlightItem': highlightItem,
    };
  }

  Widget _buildDeleteBackground() {
    return Container(
      color: Colors.red,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

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

  void _handleReceiptTap(Receipt receipt) {
    if (_isSelectingReceipts) {
      _toggleReceiptSelection(receipt.id);
      return;
    }

    Navigator.of(context).pushNamed(
      AppRoutes.receiptDetail,
      arguments: _receiptDetailArguments(receipt.id),
    );
  }

  void _handleReceiptLongPress(Receipt receipt) {
    _toggleReceiptSelection(receipt.id);
  }

  Future<String?> _pickCollectionId({
    String? excludeCollectionId,
    String title = 'Add to Trip / Event',
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

  Future<void> _assignSelectedReceiptsToCollection() async {
    if (_selectedReceiptIds.isEmpty) {
      return;
    }

    if (!ref.read(premiumCollectionAccessProvider)) {
      await _showUpgradePrompt();
      return;
    }

    final collectionId = await _pickCollectionId();
    if (!mounted || collectionId == null) {
      return;
    }

    await ref
        .read(receiptRepositoryProviderOverride)
        .assignReceiptsToCollection(_selectedReceiptIds.toList(), collectionId);
    ref.read(receiptCollectionOverridesProvider.notifier).state = {
      ...ref.read(receiptCollectionOverridesProvider),
      for (final receiptId in _selectedReceiptIds) receiptId: collectionId,
    };
    _clearReceiptSelection();
    showRootSnackBar(
      const SnackBar(content: Text('Receipts added to Trip / Event')),
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

  Future<void> _openAddToCollectionFlow(Collection collection) async {
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
                onTap: () => Navigator.of(context).pop(_AddReceiptAction.addNew),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_outlined),
                title: const Text('Select existing receipts'),
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
            initialCollectionId: collection.id,
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
        .where((receipt) => receipt.collectionId != collection.id)
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

    await ref
        .read(receiptRepositoryProviderOverride)
        .assignReceiptsToCollection(selectedIds, collection.id);
    ref.read(receiptCollectionOverridesProvider.notifier).state = {
      ...ref.read(receiptCollectionOverridesProvider),
      for (final receiptId in selectedIds) receiptId: collection.id,
    };

    showRootSnackBar(
      const SnackBar(content: Text('Receipts added to Trip / Event')),
    );
  }

  Widget _buildReceiptTile(
    Receipt receipt, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool isSelected = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryNavy.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? AppColors.primaryNavy.withValues(alpha: 0.25)
              : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          leading: _isSelectingReceipts
              ? Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? AppColors.primaryNavy
                      : AppColors.textSecondary,
                )
              : null,
          onTap: onTap,
          onLongPress: onLongPress,
          title: Text(
            receipt.storeName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            DateFormat.yMMMd().format(receipt.date),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          trailing: Builder(
            builder: (_) {
              String formattedAmount;
              try {
                formattedAmount =
                    NumberFormat.simpleCurrency(name: receipt.currency)
                        .format(receipt.total);
              } catch (_) {
                formattedAmount =
                    '${receipt.currency} ${receipt.total.toStringAsFixed(2)}';
              }
              return Text(
                formattedAmount,
                style: const TextStyle(
                  color: AppColors.accentTeal,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeHintOverlay(int index) {
    if (index != 0 || !_showSwipeHint) {
      return const SizedBox.shrink();
    }
    final hintColor = Theme.of(context).hintColor;
    return Positioned(
      top: 6,
      right: 12,
      child: GestureDetector(
        onTap: _dismissSwipeHint,
        child: Opacity(
          opacity: 0.7,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.swipe_left,
                size: 14,
                color: hintColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Swipe left to delete',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: hintColor,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final filters = ref.watch(receiptSearchFiltersProvider);
    final hasCollectionAccess = ref.watch(premiumCollectionAccessProvider);
    final collectionsAsync =
        hasCollectionAccess ? ref.watch(collectionsStreamProvider) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectingReceipts
              ? '${_selectedReceiptIds.length} selected'
              : 'My Receipts',
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryNavy,
          ),
        ),
        actions: [
          if (_isSelectingReceipts)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear selection',
              onPressed: _clearReceiptSelection,
            )
          else if (hasCollectionAccess)
            IconButton(
              icon: const Icon(
                Icons.folder_copy_outlined,
                color: AppColors.primaryNavy,
              ),
              tooltip: 'Trips & Events',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const CollectionsListScreen(),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined),
            tooltip: 'Capture receipt',
            onPressed: _handleCameraShortcut,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Account',
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.account);
            },
          ),
        ],
      ),
      body: receiptsAsync.when(
        data: (receipts) {
          final rootReceipts = receipts
              .where((receipt) => receipt.collectionId == null)
              .toList();
          _itemIndex = buildItemIndex(rootReceipts);
          final filtered = _applyFilters(rootReceipts, filters);
          final bool canClear =
              filters.query.trim().isNotEmpty || filters.hasActiveFilters;
          final bool showItemLevelResults =
              _searchQuery.isNotEmpty || filters.taxClaimable == true;

          final isAllCategory = _selectedCategory == 'All';

          return Column(
            children: [
              const SizedBox(height: 8),
              _buildSearchControls(filters),
              _buildCategoryChipBar(),
              _buildActiveFilters(filters),
              if (collectionsAsync != null)
                _buildCollectionsSection(collectionsAsync),
              Expanded(
                child: showItemLevelResults
                    ? _buildSearchResults(rootReceipts, filtered, filters)
                    : isAllCategory
                        ? (filtered.isEmpty
                            ? _EmptyState(
                                showClear: canClear,
                                onClear: () => _clearAll(clearQuery: true),
                              )
                            : _buildGroupedReceiptsList(filtered))
                        : _buildCategoryResults(rootReceipts),
              ),
            ],
          );
        },
        loading: () => Column(
          children: [
            const SizedBox(height: 8),
            _buildSearchControls(filters),
            _buildCategoryChipBar(),
            _buildActiveFilters(filters),
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
        error: (e, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            if (isNetworkException(e)) {
              await showNoInternetDialog(context);
            }
          });
          return Column(
            children: [
              const SizedBox(height: 8),
              _buildSearchControls(filters),
              _buildCategoryChipBar(),
              _buildActiveFilters(filters),
              Expanded(child: Center(child: Text('Error: $e'))),
            ],
          );
        },
      ),
      floatingActionButton: _isSelectingReceipts
          ? null
          : _AddReceiptFab(
              hasCollectionAccess: hasCollectionAccess,
              onAddReceiptPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.addReceipt),
              onCreateCollectionPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CreateCollectionScreen(),
                  ),
                );
              },
              onCollectionsPreviewPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const CollectionsPreviewScreen(),
                  ),
                );
              },
            ),
      bottomNavigationBar: _isSelectingReceipts
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _assignSelectedReceiptsToCollection,
                icon: const Icon(Icons.folder_open),
                label: const Text('Add to Trip / Event'),
              ),
            )
          : null,
    );
  }

  Widget _buildCollectionsSection(
      AsyncValue<List<Collection>> collectionsAsync) {
    return collectionsAsync.when(
      data: (collections) {
        if (collections.isEmpty) {
          return const SizedBox.shrink();
        }

        final activeCollections = collections
            .where((collection) => collection.status != CollectionStatus.completed)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final completedCollections = collections
            .where((collection) => collection.status == CollectionStatus.completed)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final displayCollections = activeCollections.length >= 5
            ? activeCollections.take(5).toList()
            : <Collection>[
                ...activeCollections,
                ...completedCollections.take(5 - activeCollections.length),
              ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Trips & Events',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isCollectionsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                    onPressed: () {
                      setState(() {
                        _isCollectionsExpanded = !_isCollectionsExpanded;
                      });
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const CollectionsListScreen(),
                        ),
                      );
                    },
                    child: const Text('See all'),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: _isCollectionsExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Column(
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: displayCollections.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final collection = displayCollections[index];
                          return _CollectionSummaryCard(
                            collection: collection,
                            fullWidth: displayCollections.length == 1,
                            onAddReceiptsPressed: () =>
                                _openAddToCollectionFlow(collection),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSearchControls(ReceiptSearchFilters filters) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: (query) {
                if (query.trim().isEmpty) return;
                AnalyticsService.logSearchUsed(
                  searchArea: 'items',
                  queryLength: query.length,
                );
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: "Search receipts",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filters.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged("");
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.accentTeal,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
            ),
            onPressed: _openFiltersSheet,
            icon: const Icon(Icons.tune),
            label: const Text("Filters"),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChipBar() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _categoryChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _categoryChips[index];
          final isSelected = item.label == _selectedCategory;
          final primaryColor = AppColors.primaryNavy;

          return ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.icon,
                  size: 22,
                  color: isSelected ? Colors.white : primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  item.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            showCheckmark: false,
            selected: isSelected,
            onSelected: (_) {
              _onCategorySelected(
                item.label == _selectedCategory ? 'All' : item.label,
              );
            },
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            selectedColor: AppColors.primaryNavy,
            backgroundColor: primaryColor.withOpacity(0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            side: BorderSide(
              color: isSelected
                  ? AppColors.primaryNavy
                  : primaryColor.withOpacity(0.08),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryResults(List<Receipt> receipts) {
    final selectedItems = _itemIndex
        .where((item) => (item.category ?? 'Other') == _selectedCategory)
        .toList();

    if (selectedItems.isEmpty) {
      return const Center(
        child: Text('No items found in this category'),
      );
    }

    final receiptCurrencyById = {
      for (final receipt in receipts) receipt.id: receipt.currency,
    };
    final groupedItems = _groupItemRowsByMonth(selectedItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '$_selectedCategory (${selectedItems.length} items)',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: groupedItems.expand((group) {
              final totalsByCurrency =
                  _monthlyTotalsByCurrency(group.items, receiptCurrencyById);
              final totalText = _formatCurrencyTotals(totalsByCurrency);

              return [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        group.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                      Text(
                        totalText,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                    ],
                  ),
                ),
                ..._buildItemGroupRows(group, receiptCurrencyById),
                const SizedBox(height: 16),
              ];
            }).toList(),
            padding: const EdgeInsets.only(bottom: 80),
          ),
        ),
      ],
    );
  }

  List<_ItemMonthGroup> _groupItemRowsByMonth(
    List<CategorisedItemView> items,
  ) {
    final sorted = List<CategorisedItemView>.from(items)
      ..sort((a, b) => b.date.compareTo(a.date));
    final grouped = <DateTime, List<CategorisedItemView>>{};

    for (final item in sorted) {
      final key = DateTime(item.date.year, item.date.month);
      grouped.putIfAbsent(key, () => <CategorisedItemView>[]).add(item);
    }

    final groups = grouped.entries.map((entry) {
      return _ItemMonthGroup(
        label: DateFormat('MMMM yyyy').format(entry.key),
        monthKey: entry.key,
        items: entry.value,
      );
    }).toList();

    groups.sort((a, b) => b.monthKey.compareTo(a.monthKey));
    return groups;
  }

  Map<String, double> _monthlyTotalsByCurrency(
    List<CategorisedItemView> items,
    Map<String, String> receiptCurrencyById,
  ) {
    final totals = <String, double>{};

    for (final item in items) {
      final currencyCode =
          _normalizeCurrencyCode(receiptCurrencyById[item.receiptId]);
      totals[currencyCode] = (totals[currencyCode] ?? 0.0) + item.price;
    }

    return totals;
  }

  Map<String, double> _monthlyTotalsByCurrencyForReceipts(
    List<Receipt> receipts,
  ) {
    final totals = <String, double>{};

    for (final receipt in receipts) {
      final currencyCode = _normalizeCurrencyCode(receipt.currency);
      totals[currencyCode] = (totals[currencyCode] ?? 0.0) + receipt.total;
    }

    return totals;
  }

  String _normalizeCurrencyCode(String? currencyCode) {
    final normalized = currencyCode?.trim() ?? '';
    return normalized.isEmpty ? 'AUD' : normalized;
  }

  String _formatCurrencyTotals(Map<String, double> totalsByCurrency) {
    final sortedEntries = totalsByCurrency.entries
        .where((entry) => entry.value != 0)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedEntries.isEmpty) return '';

    final formatter = NumberFormat('#,##0.##');
    return sortedEntries
        .map((entry) => '${entry.key} ${formatter.format(entry.value)}')
        .join(' • ');
  }

  List<Widget> _buildItemGroupRows(
    _ItemMonthGroup group,
    Map<String, String> receiptCurrencyById,
  ) {
    final rows = <Widget>[];
    final itemCount = group.items.length;

    for (var i = 0; i < itemCount; i++) {
      final item = group.items[i];
      final title = item.itemName;
      final subtitle =
          '${item.merchant} • ${DateFormat.yMMMd().format(item.date)}';
      final currencyCode =
          _normalizeCurrencyCode(receiptCurrencyById[item.receiptId]);
      final formattedPrice = NumberFormat.simpleCurrency(
        name: currencyCode,
      ).format(item.price);

      rows.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              onTap: () => _openReceipt(item),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: Text(
                formattedPrice,
                style: const TextStyle(
                  color: AppColors.accentTeal,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return rows;
  }

  Widget _buildSearchResults(
    List<Receipt> receipts,
    List<Receipt> filteredReceipts,
    ReceiptSearchFilters filters,
  ) {
    final itemResults = _searchResults(
      allowedReceiptIds: filteredReceipts.map((receipt) => receipt.id).toSet(),
      taxClaimable: filters.taxClaimable,
    );

    if (itemResults.isNotEmpty) {
      final receiptCurrencyById = {
        for (final receipt in receipts) receipt.id: receipt.currency,
      };
      final title = _searchQuery.isNotEmpty
          ? 'Search results for "${_searchQuery}" (${itemResults.length} items)'
          : 'Tax claimable items (${itemResults.length} items)';
      if (filters.taxClaimable != null) {
        final groupedItems = _groupItemRowsByMonth(itemResults);
        final totalsByCurrency =
            _monthlyTotalsByCurrency(itemResults, receiptCurrencyById);
        final totalText = _formatCurrencyTotals(totalsByCurrency);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (totalText.isNotEmpty)
                    Text(
                      totalText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 80),
                children: groupedItems.expand((group) {
                  final monthlyTotals = _monthlyTotalsByCurrency(
                    group.items,
                    receiptCurrencyById,
                  );
                  final monthlyTotalText = _formatCurrencyTotals(monthlyTotals);

                  return [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            group.label,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryNavy,
                            ),
                          ),
                          Text(
                            monthlyTotalText,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._buildItemGroupRows(group, receiptCurrencyById),
                    const SizedBox(height: 16),
                  ];
                }).toList(),
              ),
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: itemResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = itemResults[index];
                final itemTitle = _safeCanonicalName(item).isNotEmpty
                    ? _safeCanonicalName(item)
                    : _safeOriginalName(item);
                final subtitle =
                    '${item.merchant} • ${DateFormat.yMMMd().format(item.date)}';
                final formattedPrice = NumberFormat.simpleCurrency(
                  name: _currencyForReceipt(receipts, item.receiptId),
                ).format(item.price);

                return ListTile(
                  onTap: () => _openReceipt(item),
                  title: Text(itemTitle),
                  subtitle: Text(subtitle),
                  trailing: Text(formattedPrice),
                );
              },
            ),
          ),
        ],
      );
    }

    if (_searchQuery.isEmpty) {
      if (filteredReceipts.isEmpty) {
        return const Center(
          child: Text('No matching purchases found'),
        );
      }
      return _buildGroupedReceiptsList(filteredReceipts);
    }

    final receiptFallbackResults =
        _searchReceiptFallbackResults(filteredReceipts);
    if (receiptFallbackResults.isEmpty) {
      return const Center(
        child: Text('No matching purchases found'),
      );
    }

    receiptFallbackResults.sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Search results for "${_searchQuery}" (${receiptFallbackResults.length} receipts)',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: receiptFallbackResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final receipt = receiptFallbackResults[index];
              final formattedPrice = NumberFormat.simpleCurrency(
                name: receipt.currency,
              ).format(receipt.total);
              return ListTile(
                onTap: () => _handleReceiptTap(receipt),
                onLongPress: () => _handleReceiptLongPress(receipt),
                title: Text(receipt.storeName),
                subtitle: Text(
                  DateFormat.yMMMd().format(receipt.date),
                ),
                trailing: Text(formattedPrice),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Receipt> _searchReceiptFallbackResults(List<Receipt> receipts) {
    if (_searchQuery.isEmpty) return const <Receipt>[];

    final tokens = _searchQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    return receipts.where((receipt) {
      return tokens.every((token) => _matchesQuery(receipt, token));
    }).toList();
  }

  List<CategorisedItemView> _searchResults({
    Set<String>? allowedReceiptIds,
    bool? taxClaimable,
  }) {
    if (_searchQuery.isEmpty && taxClaimable == null) return const [];

    final query = _searchQuery;
    final results = _itemIndex.where((item) {
      if (allowedReceiptIds != null &&
          !allowedReceiptIds.contains(item.receiptId)) {
        return false;
      }
      if (taxClaimable != null && item.taxClaimable != taxClaimable) {
        return false;
      }
      if (_selectedCategory != 'All' &&
          (item.category ?? 'Other') != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final canonicalName = _safeCanonicalName(item).toLowerCase();
      final brand = _safeBrand(item).toLowerCase();
      final searchTokens =
          _safeSearchTokens(item).map((token) => token.toLowerCase()).toList();
      final originalName = _safeOriginalName(item).toLowerCase();
      final merchant = item.merchant.toLowerCase();
      final notes = _safeNotes(item).toLowerCase();

      return canonicalName.contains(query) ||
          brand.contains(query) ||
          searchTokens.any((token) => token.contains(query)) ||
          originalName.contains(query) ||
          merchant.contains(query) ||
          notes.contains(query);
    }).toList();

    results.sort((a, b) {
      final aRank = _searchMatchRank(a, query);
      final bRank = _searchMatchRank(b, query);
      if (aRank != bRank) return aRank.compareTo(bRank);
      return b.date.compareTo(a.date);
    });

    return results;
  }

  String _currencyForReceipt(List<Receipt> receipts, String receiptId) {
    for (final receipt in receipts) {
      if (receipt.id == receiptId) {
        return _normalizeCurrencyCode(receipt.currency);
      }
    }
    return 'AUD';
  }

  int _searchMatchRank(CategorisedItemView item, String query) {
    final canonicalName = _safeCanonicalName(item).toLowerCase();
    if (canonicalName.contains(query)) return 0;

    final brand = _safeBrand(item).toLowerCase();
    if (brand.contains(query)) return 1;

    final hasTokenMatch = _safeSearchTokens(item)
        .any((token) => token.toLowerCase().contains(query));
    if (hasTokenMatch) return 2;

    final originalName = _safeOriginalName(item).toLowerCase();
    if (originalName.contains(query)) return 3;

    final merchant = item.merchant.toLowerCase();
    if (merchant.contains(query)) return 4;

    return 5;
  }

  String _safeCanonicalName(CategorisedItemView item) {
    try {
      final dynamicItem = item as dynamic;
      final value = dynamicItem.canonicalName;
      return value is String ? value : '';
    } catch (_) {
      return '';
    }
  }

  String _safeOriginalName(CategorisedItemView item) {
    return item.itemName;
  }

  String _safeBrand(CategorisedItemView item) {
    try {
      final dynamicItem = item as dynamic;
      final value = dynamicItem.brand;
      return value is String ? value : '';
    } catch (_) {
      return '';
    }
  }

  List<String> _safeSearchTokens(CategorisedItemView item) {
    try {
      final dynamicItem = item as dynamic;
      final value = dynamicItem.searchTokens;
      if (value is List) {
        return value.whereType<String>().toList();
      }
      return const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  String _safeNotes(CategorisedItemView item) {
    try {
      final dynamicItem = item as dynamic;
      final value = dynamicItem.notes;
      return value is String ? value : '';
    } catch (_) {
      return '';
    }
  }

  void _openReceipt(CategorisedItemView item) {
    Navigator.of(context).pushNamed(
      AppRoutes.receiptDetail,
      arguments: _receiptDetailArguments(
        item.receiptId,
        highlightCategory: item.category ?? 'Other',
        highlightItem: item.itemName,
      ),
    );
  }

  Widget _buildActiveFilters(ReceiptSearchFilters filters) {
    final chips = <Widget>[];
    final dateFormat = DateFormat.yMMMd();

    if (filters.store != null && filters.store!.trim().isNotEmpty) {
      chips.add(
        Chip(
          label: Text("Store: ${filters.store}"),
          onDeleted: () => _updateFilters(
            filters.copyWith(store: null),
          ),
        ),
      );
    }

    if (filters.startDate != null || filters.endDate != null) {
      final startText = filters.startDate != null
          ? dateFormat.format(filters.startDate!)
          : "Any";
      final endText =
          filters.endDate != null ? dateFormat.format(filters.endDate!) : "Any";
      chips.add(
        Chip(
          label: Text("Date: $startText – $endText"),
          onDeleted: () => _updateFilters(
            filters.copyWith(startDate: null, endDate: null),
          ),
        ),
      );
    }

    if (filters.minTotal != null) {
      chips.add(
        Chip(
          label: Text("Min \$${filters.minTotal!.toStringAsFixed(2)}"),
          onDeleted: () => _updateFilters(filters.copyWith(minTotal: null)),
        ),
      );
    }

    if (filters.maxTotal != null) {
      chips.add(
        Chip(
          label: Text("Max \$${filters.maxTotal!.toStringAsFixed(2)}"),
          onDeleted: () => _updateFilters(filters.copyWith(maxTotal: null)),
        ),
      );
    }

    if (filters.taxClaimable != null) {
      chips.add(
        Chip(
          label: Text(
            "Tax claimable: ${filters.taxClaimable! ? "Yes" : "No"}",
          ),
          onDeleted: () => _updateFilters(filters.copyWith(taxClaimable: null)),
        ),
      );
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _clearAll(clearQuery: false),
              child: const Text("Clear all"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedReceiptsList(List<Receipt> receipts) {
    final monthGroups = _groupReceiptsByMonth(receipts);
    final children = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          'Receipts',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryNavy,
          ),
        ),
      ),
    ];
    var overallIndex = 0;

    for (var groupIndex = 0; groupIndex < monthGroups.length; groupIndex++) {
      final group = monthGroups[groupIndex];
      final totalsByCurrency =
          _monthlyTotalsByCurrencyForReceipts(group.receipts);
      final totalText = _formatCurrencyTotals(totalsByCurrency);
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                group.label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                ),
              ),
              Text(
                totalText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                ),
              ),
            ],
          ),
        ),
      );

      for (final receipt in group.receipts) {
        final currentIndex = overallIndex++;
        final isSelected = _selectedReceiptIds.contains(receipt.id);
        final receiptTile = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Stack(
            children: [
              _buildReceiptTile(
                receipt,
                onTap: () => _handleReceiptTap(receipt),
                onLongPress: () => _handleReceiptLongPress(receipt),
                isSelected: isSelected,
              ),
              if (!_isSelectingReceipts) _buildSwipeHintOverlay(currentIndex),
            ],
          ),
        );

        if (_isSelectingReceipts) {
          children.add(receiptTile);
          continue;
        }

        children.add(
          Dismissible(
            key: ValueKey(receipt.id),
            background: _buildDeleteBackground(),
            secondaryBackground: _buildDeleteBackground(),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              final connectivity = ref.read(connectivityServiceProvider);
              if (!await ensureInternetConnection(context, connectivity)) {
                return false;
              }
              if (!mounted) return false;
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Delete Receipt"),
                      content: const Text(
                          "Are you sure you want to delete this receipt?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text("Delete"),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            onDismissed: (_) async {
              try {
                await ref
                    .read(receiptRepositoryProviderOverride)
                    .deleteReceipt(receipt.id);
              } catch (e) {
                if (isNetworkException(e)) {
                  if (mounted) {
                    await showNoInternetDialog(context);
                  }
                  return;
                }
                rethrow;
              }

              _dismissSwipeHint();
              showRootSnackBar(
                const SnackBar(content: Text("Receipt deleted")),
              );
            },
            child: receiptTile,
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: children,
    );
  }

  List<_MonthGroup> _groupReceiptsByMonth(List<Receipt> receipts) {
    final sorted = List<Receipt>.from(receipts)
      ..sort((a, b) => b.date.compareTo(a.date));
    final grouped = <DateTime, List<Receipt>>{};

    for (final receipt in sorted) {
      final key = DateTime(receipt.date.year, receipt.date.month);
      grouped.putIfAbsent(key, () => <Receipt>[]).add(receipt);
    }

    return grouped.entries.map((entry) {
      return _MonthGroup(
        label: DateFormat('MMMM yyyy').format(entry.key),
        receipts: entry.value,
      );
    }).toList();
  }

  void _onQueryChanged(String value) {
    final notifier = ref.read(receiptSearchFiltersProvider.notifier);
    notifier.state = notifier.state.copyWith(query: value);
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value.trim().toLowerCase();
    });
    _onQueryChanged(value);
  }

  void _updateFilters(ReceiptSearchFilters filters) {
    final currentFilters = ref.read(receiptSearchFiltersProvider);
    final didEnableTaxClaimable =
        currentFilters.taxClaimable == null && filters.taxClaimable != null;

    if (didEnableTaxClaimable && _selectedCategory != 'All') {
      setState(() {
        _selectedCategory = 'All';
      });
    }

    ref.read(receiptSearchFiltersProvider.notifier).state =
        filters.copyWith(query: _searchController.text);
  }

  void _clearAll({required bool clearQuery}) {
    final notifier = ref.read(receiptSearchFiltersProvider.notifier);
    final next = clearQuery
        ? const ReceiptSearchFilters()
        : notifier.state.clearFilters();
    notifier.state = next;
    if (clearQuery) {
      _searchController.clear();
      setState(() {
        _searchQuery = '';
      });
    }
  }

  Future<void> _openFiltersSheet() async {
    final current = ref.read(receiptSearchFiltersProvider);
    final result = await showModalBottomSheet<ReceiptSearchFilters>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ReceiptFiltersSheet(initialFilters: current),
    );

    if (result != null) {
      _updateFilters(result);
    }
  }

  List<Receipt> _applyFilters(
    List<Receipt> receipts,
    ReceiptSearchFilters filters,
  ) {
    final lowerQuery = filters.query.trim().toLowerCase();
    final tokens =
        lowerQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    return receipts.where((receipt) {
      if (tokens.isNotEmpty) {
        final matchesAllTokens =
            tokens.every((token) => _matchesQuery(receipt, token));
        if (!matchesAllTokens) {
          return false;
        }
      }

      if (filters.store != null && filters.store!.trim().isNotEmpty) {
        final storeQuery = filters.store!.trim().toLowerCase();
        if (!receipt.storeName.toLowerCase().contains(storeQuery)) {
          return false;
        }
      }

      final receiptDate = DateUtils.dateOnly(receipt.date);

      if (filters.startDate != null &&
          receiptDate.isBefore(DateUtils.dateOnly(filters.startDate!))) {
        return false;
      }

      if (filters.endDate != null &&
          receiptDate.isAfter(DateUtils.dateOnly(filters.endDate!))) {
        return false;
      }

      if (filters.minTotal != null && receipt.total < filters.minTotal!) {
        return false;
      }

      if (filters.maxTotal != null && receipt.total > filters.maxTotal!) {
        return false;
      }

      if (filters.taxClaimable != null) {
        final hasTaxClaimable = receipt.items.any((i) => i.taxClaimable);
        if (filters.taxClaimable! && !hasTaxClaimable) return false;
        if (!filters.taxClaimable! && hasTaxClaimable) return false;
      }

      return true;
    }).toList();
  }

  Future<void> _handleCameraShortcut() async {
    final navigator = Navigator.of(context);
    final connectivity = ref.read(connectivityServiceProvider);
    final hasInternet = await ensureInternetConnection(context, connectivity);
    if (!hasInternet) return;
    final imageService = ref.read(receiptImageSourceServiceProvider);
    final result = await imageService.pickFromCamera();
    if (!mounted) return;

    if (result.file != null) {
      await navigator.pushNamed(
        AppRoutes.addReceipt,
        arguments: AddReceiptScreenArgs(initialImagePath: result.file!.path),
      );
      return;
    }

    final failure = result.failure;
    if (failure == null) return;

    if (failure.code == ReceiptImageSourceError.permissionDenied) {
      showRootSnackBar(
        SnackBar(content: Text(failure.message)),
      );
      return;
    }

    final selection = await imageService.showCameraFallbackDialog(context);
    if (!mounted || selection == null) return;

    late final AddReceiptScreenArgs args;
    switch (selection) {
      case CameraFallbackSelection.gallery:
        args = const AddReceiptScreenArgs(
          initialAction: AddReceiptInitialAction.pickGallery,
        );
      case CameraFallbackSelection.files:
        args = const AddReceiptScreenArgs(
          initialAction: AddReceiptInitialAction.pickFiles,
        );
    }
    await navigator.pushNamed(
      AppRoutes.addReceipt,
      arguments: args,
    );
  }

  bool _matchesQuery(Receipt receipt, String query) {
    if (receipt.storeName.toLowerCase().contains(query)) {
      return true;
    }

    if (receipt.searchKeywords.any((k) => k.toLowerCase().contains(query))) {
      return true;
    }

    if (receipt.items.any((item) => item.name.toLowerCase().contains(query))) {
      return true;
    }

    final notes = receipt.notes ?? '';
    if (notes.toLowerCase().contains(query)) {
      return true;
    }

    final dateString = DateFormat.yMMMd().format(receipt.date).toLowerCase();
    if (dateString.contains(query)) {
      return true;
    }

    final totalString = receipt.total.toStringAsFixed(2);
    if (totalString.contains(query)) {
      return true;
    }

    return false;
  }
}

class _MonthGroup {
  final String label;
  final List<Receipt> receipts;

  const _MonthGroup({
    required this.label,
    required this.receipts,
  });
}

class _ItemMonthGroup {
  final String label;
  final DateTime monthKey;
  final List<CategorisedItemView> items;

  const _ItemMonthGroup({
    required this.label,
    required this.monthKey,
    required this.items,
  });
}

class _AddReceiptFab extends StatelessWidget {
  const _AddReceiptFab({
    required this.hasCollectionAccess,
    required this.onAddReceiptPressed,
    required this.onCreateCollectionPressed,
    required this.onCollectionsPreviewPressed,
  });

  final bool hasCollectionAccess;
  final VoidCallback onAddReceiptPressed;
  final VoidCallback onCreateCollectionPressed;
  final VoidCallback onCollectionsPreviewPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: "addReceiptFab",
      onPressed: () => _showActions(context),
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<_HomeFabAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Add Receipt'),
                onTap: () =>
                    Navigator.of(context).pop(_HomeFabAction.addReceipt),
              ),
              ListTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: const Text('Create Trip or Event'),
                onTap: () =>
                    Navigator.of(context).pop(_HomeFabAction.createCollection),
              ),
            ],
          ),
        );
      },
    );

    if (action == _HomeFabAction.addReceipt) {
      onAddReceiptPressed();
      return;
    }

    if (action == _HomeFabAction.createCollection) {
      if (hasCollectionAccess) {
        onCreateCollectionPressed();
      } else {
        onCollectionsPreviewPressed();
      }
    }
  }
}

class _CollectionSummaryCard extends ConsumerWidget {
  const _CollectionSummaryCard({
    required this.collection,
    required this.onAddReceiptsPressed,
    this.fullWidth = false,
  });

  final Collection collection;
  final VoidCallback onAddReceiptsPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider).maybeWhen(
          data: (List<Receipt> receipts) => receipts,
          orElse: () => const <Receipt>[],
        );
    final isCompleted = collection.status == CollectionStatus.completed;
    final collectionReceipts = receipts
        .where((receipt) => receipt.collectionId == collection.id)
        .toList();
    final receiptCount = collectionReceipts.length;
    final hasReceipts = collectionReceipts.isNotEmpty;
    final dateLabel = _buildDateLabel(collection);

    return SizedBox(
      width: fullWidth ? double.infinity : 200,
      height: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isCompleted ? 0.03 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isCompleted
                  ? Colors.grey.shade300
                  : Colors.grey.shade200,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CollectionDetailScreen(collectionId: collection.id),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.folder_copy_outlined,
                          size: 18,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          collection.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        collection.type == CollectionType.work
                            ? 'Work'
                            : 'Personal',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.accentTeal,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isCompleted ? 'Completed' : 'Active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isCompleted
                              ? Colors.grey.shade600
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (dateLabel != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dateLabel,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const Spacer(),
                  if (hasReceipts)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$receiptCount receipt${receiptCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: AppColors.primaryNavy,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onAddReceiptsPressed,
                          child: const Text('+ Add'),
                        ),
                      ],
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No receipts yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryNavy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: TextButton(
                            onPressed: onAddReceiptsPressed,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Add receipts',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryNavy,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _buildDateLabel(Collection collection) {
  if (collection.startDate == null && collection.endDate == null) {
    return null;
  }

  final formatter = DateFormat.yMMMd();
  if (collection.startDate != null && collection.endDate == null) {
    return 'Starts ${formatter.format(collection.startDate!)}';
  }

  final startText = collection.startDate == null
      ? 'Any start'
      : formatter.format(collection.startDate!);
  final endText = collection.endDate == null
      ? 'Any end'
      : formatter.format(collection.endDate!);
  return '$startText - $endText';
}

enum _HomeFabAction {
  addReceipt,
  createCollection,
}

enum _AddReceiptAction { addNew, addExisting }

class _EmptyState extends StatelessWidget {
  final bool showClear;
  final VoidCallback onClear;
  const _EmptyState({required this.showClear, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            'No receipts found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          if (showClear) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear search & filters'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptFiltersSheet extends StatefulWidget {
  final ReceiptSearchFilters initialFilters;
  const _ReceiptFiltersSheet({required this.initialFilters});

  @override
  State<_ReceiptFiltersSheet> createState() => _ReceiptFiltersSheetState();
}

class _ReceiptFiltersSheetState extends State<_ReceiptFiltersSheet> {
  late final TextEditingController _storeController;
  late final TextEditingController _minTotalController;
  late final TextEditingController _maxTotalController;
  DateTime? _startDate;
  DateTime? _endDate;
  bool? _taxClaimable;

  @override
  void initState() {
    super.initState();
    _storeController =
        TextEditingController(text: widget.initialFilters.store ?? "");
    _minTotalController = TextEditingController(
      text: widget.initialFilters.minTotal?.toString() ?? "",
    );
    _maxTotalController = TextEditingController(
      text: widget.initialFilters.maxTotal?.toString() ?? "",
    );
    _startDate = widget.initialFilters.startDate;
    _endDate = widget.initialFilters.endDate;
    _taxClaimable = widget.initialFilters.taxClaimable;
  }

  @override
  void dispose() {
    _storeController.dispose();
    _minTotalController.dispose();
    _maxTotalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final dateFormat = DateFormat.yMMMd();

    return Padding(
      padding: EdgeInsets.only(
        bottom: viewInsets,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Filters",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _storeController,
              decoration: const InputDecoration(
                labelText: "Store",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minTotalController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Min total",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxTotalController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Max total",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DatePickerTile(
                    label: "Start date",
                    value: _startDate != null
                        ? dateFormat.format(_startDate!)
                        : "Any",
                    onClear: _startDate == null
                        ? null
                        : () => setState(() => _startDate = null),
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DatePickerTile(
                    label: "End date",
                    value:
                        _endDate != null ? dateFormat.format(_endDate!) : "Any",
                    onClear: _endDate == null
                        ? null
                        : () => setState(() => _endDate = null),
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool?>(
              initialValue: _taxClaimable,
              decoration: const InputDecoration(
                labelText: "Tax claimable",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text("Any"),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text("Yes"),
                ),
                DropdownMenuItem(
                  value: false,
                  child: Text("No"),
                ),
              ],
              onChanged: (value) => setState(() => _taxClaimable = value),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text("Reset"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text("Apply"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _reset() {
    setState(() {
      _storeController.clear();
      _minTotalController.clear();
      _maxTotalController.clear();
      _startDate = null;
      _endDate = null;
      _taxClaimable = null;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      widget.initialFilters.copyWith(
        store: _storeController.text.trim().isEmpty
            ? null
            : _storeController.text.trim(),
        minTotal: _parseDouble(_minTotalController.text),
        maxTotal: _parseDouble(_maxTotalController.text),
        startDate: _startDate,
        endDate: _endDate,
        taxClaimable: _taxClaimable,
      ),
    );
  }

  double? _parseDouble(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onClear;
  final VoidCallback onTap;

  const _DatePickerTile({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(value),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 18),
              ),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }
}

class _CategoryChipItem {
  final String label;
  final IconData icon;

  const _CategoryChipItem({
    required this.label,
    required this.icon,
  });
}
