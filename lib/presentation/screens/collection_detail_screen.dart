import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
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
  final Set<String> _selectedReceiptIds = <String>{};

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _collectionTypeLabel(collection.type),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildDateSection(collection),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                '${receipts.length} receipts',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _buildCurrencyTotals(receipts),
              const SizedBox(height: 12),
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
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryCard(collection, receipts),
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
                          Expanded(
                            child: receipts.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No receipts in this collection yet',
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      96,
                                    ),
                                    itemCount: receipts.length,
                                    itemBuilder: (context, index) {
                                      final receipt = receipts[index];
                                      final isSelected = _selectedReceiptIds
                                          .contains(receipt.id);

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Card(
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
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
                                            onTap: () =>
                                                _handleReceiptTap(receipt),
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
                                                        : AppColors
                                                            .textSecondary,
                                                  )
                                                : null,
                                            title: Text(
                                              receipt.storeName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Text(
                                              DateFormat.yMMMd()
                                                  .format(receipt.date),
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
                          ),
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
