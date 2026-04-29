import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/presentation/providers/providers.dart';

enum CollectionPickerActionType { selected, createNew }

class CollectionPickerAction {
  const CollectionPickerAction.selected(this.collectionId)
      : type = CollectionPickerActionType.selected;

  const CollectionPickerAction.createNew()
      : type = CollectionPickerActionType.createNew,
        collectionId = null;

  final CollectionPickerActionType type;
  final String? collectionId;
}

Future<CollectionPickerAction?> showCollectionPickerBottomSheet(
  BuildContext context, {
  String? excludeCollectionId,
  String title = 'Add to Trip / Event',
  String createLabel = 'Create New Trip / Event',
}) {
  return showModalBottomSheet<CollectionPickerAction>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return Consumer(
        builder: (context, ref, _) {
          final collectionsAsync = ref.watch(collectionsProvider);

          return collectionsAsync.when(
            loading: () => const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, _) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Failed to load collections: $error'),
                  ],
                ),
              ),
            ),
            data: (collections) {
              final visibleCollections = collections
                  .where((collection) => collection.id != excludeCollectionId)
                  .toList();

              if (visibleCollections.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(
                      context,
                    ).pop(const CollectionPickerAction.createNew());
                  }
                });
                return const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final collection in visibleCollections)
                            ListTile(
                              leading: const Icon(
                                Icons.folder_open,
                                color: AppColors.primaryNavy,
                              ),
                              title: Text(collection.name),
                              subtitle: Text(
                                collection.type == CollectionType.work
                                    ? 'Work'
                                    : 'Personal',
                              ),
                              onTap: () {
                                Navigator.of(context).pop(
                                  CollectionPickerAction.selected(
                                    collection.id,
                                  ),
                                );
                              },
                            ),
                          ListTile(
                            leading: const Icon(
                              Icons.add_circle_outline,
                              color: AppColors.primaryNavy,
                            ),
                            title: Text(createLabel),
                            onTap: () {
                              Navigator.of(context).pop(
                                const CollectionPickerAction.createNew(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

Future<List<String>?> showReceiptSelectionBottomSheet(
  BuildContext context, {
  required List<Receipt> receipts,
  required String title,
  required String ctaLabel,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _ReceiptSelectionSheet(
        receipts: receipts,
        title: title,
        ctaLabel: ctaLabel,
      );
    },
  );
}

class _ReceiptSelectionSheet extends StatefulWidget {
  const _ReceiptSelectionSheet({
    required this.receipts,
    required this.title,
    required this.ctaLabel,
  });

  final List<Receipt> receipts;
  final String title;
  final String ctaLabel;

  @override
  State<_ReceiptSelectionSheet> createState() => _ReceiptSelectionSheetState();
}

class _ReceiptSelectionSheetState extends State<_ReceiptSelectionSheet> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                  ),
                  Text(
                    '${_selectedIds.length} selected',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.receipts.isEmpty
                  ? const Center(
                      child: Text('No receipts available.'),
                    )
                  : ListView.builder(
                      itemCount: widget.receipts.length,
                      itemBuilder: (context, index) {
                        final receipt = widget.receipts[index];
                        final selected = _selectedIds.contains(receipt.id);
                        return CheckboxListTile(
                          value: selected,
                          title: Text(receipt.storeName),
                          subtitle: Text(
                            '${receipt.currency} ${receipt.total.toStringAsFixed(2)}',
                          ),
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedIds.remove(receipt.id);
                              } else {
                                _selectedIds.add(receipt.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selectedIds.toList()),
                  child: Text(widget.ctaLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
