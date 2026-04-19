import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receiptnest/core/services/analytics_service.dart';
import 'package:receiptnest/core/utils/app_logger.dart';
import 'package:receiptnest/domain/services/export/export_context.dart';
import 'package:receiptnest/domain/services/export/export_exception.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/providers/receipt_search_filters_provider.dart';
import 'package:receiptnest/presentation/routes/app_routes.dart';
import 'package:receiptnest/presentation/screens/add_receipt_screen.dart';
import 'package:receiptnest/presentation/screens/collections_list_screen.dart';
import 'package:receiptnest/presentation/screens/collections_preview_screen.dart';
import 'package:receiptnest/presentation/screens/create_collection_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';
import 'package:receiptnest/presentation/utils/root_scaffold_messenger.dart';
import 'package:receiptnest/presentation/widgets/export_ready_sheet.dart';
import 'package:receiptnest/presentation/widgets/smart_prompt_card.dart';
import 'package:receiptnest/services/receipt_image_source_service.dart';
import 'package:receiptnest/domain/models/categorised_item_view.dart';
import 'package:receiptnest/domain/utils/item_index_builder.dart';

class ReceiptListScreen extends ConsumerStatefulWidget {
  const ReceiptListScreen({super.key});

  @override
  ConsumerState<ReceiptListScreen> createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends ConsumerState<ReceiptListScreen> {
  late final TextEditingController _searchController;
  static const String _swipeHintPrefKey = 'receipt_swipe_hint_shown';
  bool _showSwipeHint = false;
  bool _showTaxExportPrompt = true;
  bool _isExporting = false;
  List<CategorisedItemView> _itemIndex = const [];

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

  Widget _buildReceiptTile(Receipt receipt) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/receiptDetail',
            arguments: receipt.id,
          );
        },
        title: Text(
          receipt.storeName,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          DateFormat.yMMMd().format(receipt.date),
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
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            );
          },
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
    final searchQuery = filters.query.trim().toLowerCase();
    final hasCollectionAccess = ref.watch(premiumCollectionAccessProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "My Receipts",
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryNavy,
          ),
        ),
        actions: [
          if (hasCollectionAccess)
            IconButton(
              icon: const Icon(
                Icons.folder_open,
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
          final filtered = _applyFilters(rootReceipts, filters);
          _itemIndex = buildItemIndex(filtered);
          final bool canClear =
              filters.query.trim().isNotEmpty || filters.hasActiveFilters;
          final bool showItemLevelResults =
              searchQuery.isNotEmpty || filters.taxClaimable == true;
          final bool shouldShowTaxExportPrompt = filters.taxClaimable != null &&
              filtered.isNotEmpty &&
              _showTaxExportPrompt;

          return Column(
            children: [
              const SizedBox(height: 8),
              _buildSearchControls(filters),
              _buildActiveFilters(filters),
              if (shouldShowTaxExportPrompt)
                SmartPromptCard(
                  icon: Icons.receipt_long,
                  title: 'Preparing your tax records?',
                  description:
                      'Download all tax claimable receipts for easy filing.',
                  primaryActionText: 'Export tax receipts',
                  onPrimaryAction: _isExporting
                      ? null
                      : () => _exportFilteredReceipts(filtered),
                  secondaryActionText: 'Not now',
                  onSecondaryAction: () {
                    setState(() => _showTaxExportPrompt = false);
                  },
                ),
              Expanded(
                child: showItemLevelResults
                    ? _buildSearchResults(filtered, searchQuery, filters)
                    : filtered.isEmpty
                        ? _EmptyState(
                            showClear: canClear,
                            onClear: () => _clearAll(clearQuery: true),
                          )
                        : _buildGroupedReceiptsList(filtered),
              ),
            ],
          );
        },
        loading: () => Column(
          children: [
            const SizedBox(height: 8),
            _buildSearchControls(filters),
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
              _buildActiveFilters(filters),
              Expanded(child: Center(child: Text('Error: $e'))),
            ],
          );
        },
      ),
      floatingActionButton: _AddReceiptFab(
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
              onChanged: _onQueryChanged,
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
                          _onQueryChanged("");
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

  Widget _buildSearchResults(
    List<Receipt> receipts,
    String query,
    ReceiptSearchFilters filters,
  ) {
    final itemResults = _searchResults(
      query,
      taxClaimable: filters.taxClaimable,
    );

    if (itemResults.isNotEmpty) {
      final title = query.isNotEmpty
          ? 'Search results for "$query" (${itemResults.length} items)'
          : 'Tax claimable items (${itemResults.length} items)';
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
                final subtitle =
                    '${item.merchant} • ${DateFormat.yMMMd().format(item.date)}';
                final formattedPrice = NumberFormat.simpleCurrency(
                  name: _currencyForReceipt(receipts, item.receiptId),
                ).format(item.price);

                return ListTile(
                  onTap: () => Navigator.of(context).pushNamed(
                    '/receiptDetail',
                    arguments: item.receiptId,
                  ),
                  title: Text(item.itemName),
                  subtitle: Text(subtitle),
                  trailing: Text(formattedPrice),
                );
              },
            ),
          ),
        ],
      );
    }

    if (query.isEmpty) {
      return receipts.isEmpty
          ? const Center(child: Text('No matching purchases found'))
          : _buildGroupedReceiptsList(receipts);
    }

    final receiptFallbackResults =
        _searchReceiptFallbackResults(receipts, query);
    if (receiptFallbackResults.isEmpty) {
      return const Center(
        child: Text('No matching purchases found'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Search results for "$query" (${receiptFallbackResults.length} receipts)',
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
                onTap: () => Navigator.of(context).pushNamed(
                  '/receiptDetail',
                  arguments: receipt.id,
                ),
                title: Text(receipt.storeName),
                subtitle: Text(DateFormat.yMMMd().format(receipt.date)),
                trailing: Text(formattedPrice),
              );
            },
          ),
        ),
      ],
    );
  }

  List<CategorisedItemView> _searchResults(
    String query, {
    bool? taxClaimable,
  }) {
    if (query.isEmpty && taxClaimable == null) return const [];

    final results = _itemIndex.where((item) {
      if (taxClaimable != null && item.taxClaimable != taxClaimable) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final itemName = item.itemName.toLowerCase();
      final merchant = item.merchant.toLowerCase();

      return itemName.contains(query) || merchant.contains(query);
    }).toList();
    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  String _currencyForReceipt(List<Receipt> receipts, String receiptId) {
    for (final receipt in receipts) {
      if (receipt.id == receiptId) {
        final normalizedCurrency = receipt.currency.trim();
        return normalizedCurrency.isEmpty ? 'AUD' : normalizedCurrency;
      }
    }
    return 'AUD';
  }

  List<Receipt> _searchReceiptFallbackResults(
      List<Receipt> receipts, String query) {
    if (query.isEmpty) return const <Receipt>[];
    final tokens =
        query.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();
    return receipts.where((receipt) {
      return tokens.every((token) => _matchesQuery(receipt, token));
    }).toList();
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
    final children = <Widget>[];
    var overallIndex = 0;

    for (var groupIndex = 0; groupIndex < monthGroups.length; groupIndex++) {
      final group = monthGroups[groupIndex];
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            group.label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
      );

      for (final receipt in group.receipts) {
        final currentIndex = overallIndex++;
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Stack(
                children: [
                  _buildReceiptTile(receipt),
                  _buildSwipeHintOverlay(currentIndex),
                ],
              ),
            ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
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

  void _updateFilters(ReceiptSearchFilters filters) {
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
    }
  }

  Future<void> _exportFilteredReceipts(List<Receipt> receipts) async {
    if (_isExporting || receipts.isEmpty) {
      return;
    }

    setState(() => _isExporting = true);

    try {
      final exportService = ref.read(receiptExportServiceProvider);
      final searchQuery = _searchController.text.trim();
      final title =
          searchQuery.isNotEmpty ? 'tax_evidence_$searchQuery' : 'tax_evidence';

      final result = await exportService.prepareExport(
        receipts: receipts,
        context: ExportContext.search(title: title),
      );
      if (!mounted) return;
      setState(() => _showTaxExportPrompt = false);

      final action = await showExportReadySheet(
        context,
        skippedReceiptCount: result.skippedReceiptIds.length,
        debugBytesLength: result.fileBytes?.length,
      );
      if (!mounted || action == null) {
        return;
      }

      if (action == ExportReadyAction.save) {
        try {
          final savedPath =
              await exportService.saveExportToDevice(result: result);

          if (!mounted) return;
          if (savedPath != null) {
            final fileName =
                result.fileName.isNotEmpty ? result.fileName : 'file';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Export "$fileName" saved to your device'),
              ),
            );
          }
        } catch (e) {
          AppLogger.error('Export save failed: $e');
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save export. Please try again.'),
            ),
          );
        }
        return;
      }

      await exportService.shareExport(
        result: result,
        shareContext: context,
      );
    } on ExportException catch (error) {
      showRootSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      showRootSnackBar(
        const SnackBar(content: Text('Unable to prepare export right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
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

enum _HomeFabAction {
  addReceipt,
  createCollection,
}

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
