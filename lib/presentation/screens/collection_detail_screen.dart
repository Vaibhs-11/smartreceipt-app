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

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CollectionSummaryCard(collection: collection),
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
                              TextButton.icon(
                                onPressed: _showAddReceiptSheet,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Receipt'),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: receiptsAsync.when(
                          data: (receipts) {
                            if (receipts.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No receipts in this collection yet',
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              itemCount: receipts.length,
                              itemBuilder: (context, index) {
                                final receipt = receipts[index];
                                final isSelected =
                                    _selectedReceiptIds.contains(receipt.id);

                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
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
                                          _toggleReceiptSelection(receipt.id),
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
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => Center(
                            child: Text('Failed to load receipts: $error'),
                          ),
                        ),
                      ),
                    ],
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

class _CollectionSummaryCard extends StatelessWidget {
  const _CollectionSummaryCard({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final dateRange = _formatCollectionDateRange(collection);
    final updatedAt = DateFormat.yMMMd().format(collection.updatedAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                collection.type == CollectionType.work ? 'Work' : 'Personal',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              if (dateRange != null) ...[
                const SizedBox(height: 8),
                Text(
                  dateRange,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              if (collection.notes != null &&
                  collection.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  collection.notes!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Updated $updatedAt',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

String? _formatCollectionDateRange(Collection collection) {
  if (collection.startDate == null && collection.endDate == null) {
    return null;
  }

  final formatter = DateFormat.yMMMd();
  final startText = collection.startDate == null
      ? 'Any start'
      : formatter.format(collection.startDate!);
  final endText = collection.endDate == null
      ? 'Any end'
      : formatter.format(collection.endDate!);
  return '$startText - $endText';
}
