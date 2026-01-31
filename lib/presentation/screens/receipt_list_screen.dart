import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/providers/receipt_search_filters_provider.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/add_receipt_screen.dart';
import 'package:smartreceipt/services/receipt_image_source_service.dart';

class ReceiptListScreen extends ConsumerStatefulWidget {
  const ReceiptListScreen({super.key});

  @override
  ConsumerState<ReceiptListScreen> createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends ConsumerState<ReceiptListScreen> {
  late final TextEditingController _searchController;
  static const String _swipeHintPrefKey = 'receipt_swipe_hint_shown';
  bool _showSwipeHint = false;

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
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
              ?.copyWith(fontWeight: FontWeight.bold),
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
              style: TextStyle(
                color: Colors.green[700],
                fontWeight: FontWeight.bold,
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
    return Positioned(
      top: 6,
      right: 12,
      child: GestureDetector(
        onTap: _dismissSwipeHint,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.swipe_left,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 6),
              Text(
                'Swipe left to delete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Receipts"),
        actions: [
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
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              ref.read(receiptSearchFiltersProvider.notifier).state =
                  const ReceiptSearchFilters();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchControls(filters),
          _buildActiveFilters(filters),
          Expanded(
            child: receiptsAsync.when(
              data: (receipts) {
                final filtered = _applyFilters(receipts, filters);
                if (filtered.isEmpty) {
                  final bool canClear = filters.query.trim().isNotEmpty ||
                      filters.hasActiveFilters;
                  return _EmptyState(
                    showClear: canClear,
                    onClear: () => _clearAll(clearQuery: true),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final receipt = filtered[index];
                    return Dismissible(
                      key: ValueKey(receipt.id),
                      background: _buildDeleteBackground(),
                      secondaryBackground: _buildDeleteBackground(),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
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
                        await ref
                            .read(receiptRepositoryProviderOverride)
                            .deleteReceipt(receipt.id);

                        _dismissSwipeHint();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Receipt deleted")),
                        );
                      },
                      child: Stack(
                        children: [
                          _buildReceiptTile(receipt),
                          _buildSwipeHintOverlay(index),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: _AddReceiptFab(
        onPressed: () => Navigator.pushNamed(context, '/addReceipt'),
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _openFiltersSheet,
            icon: const Icon(Icons.tune),
            label: const Text("Filters"),
          ),
        ],
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
    return receipts.where((receipt) {
      if (lowerQuery.isNotEmpty && !_matchesQuery(receipt, lowerQuery)) {
        return false;
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
    final messenger = ScaffoldMessenger.of(context);
    final imageService = ref.read(receiptImageSourceServiceProvider);
    final result = await imageService.pickFromCamera();
    if (!mounted) return;

    if (result.file != null) {
      await navigator.pushNamed(
        AppRoutes.addReceipt,
        arguments:
            AddReceiptScreenArgs(initialImagePath: result.file!.path),
      );
      return;
    }

    final failure = result.failure;
    if (failure == null) return;

    if (failure.code == ReceiptImageSourceError.permissionDenied) {
      messenger.showSnackBar(
        SnackBar(content: Text(failure.message)),
      );
      return;
    }

    final selection = await imageService.showCameraFallbackDialog(context);
    if (!mounted || selection == null) return;

    AddReceiptScreenArgs? args;
    switch (selection) {
      case CameraFallbackSelection.gallery:
        args = const AddReceiptScreenArgs(
          initialAction: AddReceiptInitialAction.pickGallery,
        );
        break;
      case CameraFallbackSelection.files:
        args = const AddReceiptScreenArgs(
          initialAction: AddReceiptInitialAction.pickFiles,
        );
        break;
    }

    if (args != null) {
      await navigator.pushNamed(
        AppRoutes.addReceipt,
        arguments: args,
      );
    }
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

class _AddReceiptFab extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddReceiptFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: "addReceiptFab",
      onPressed: onPressed,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }
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
              value: _taxClaimable,
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
