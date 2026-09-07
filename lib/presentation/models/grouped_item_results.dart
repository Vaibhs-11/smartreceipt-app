import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/models/categorised_item_view.dart';

class ItemResultMonthGroup {
  const ItemResultMonthGroup({
    required this.monthKey,
    required this.receipts,
  });

  final DateTime monthKey;
  final List<ItemResultReceiptGroup> receipts;
}

class ItemResultReceiptGroup {
  const ItemResultReceiptGroup({
    required this.receipt,
    required this.items,
  });

  final Receipt receipt;
  final List<CategorisedItemView> items;

  double get displayedSubtotal {
    if (items.isEmpty) {
      return receipt.total;
    }
    return items.fold<double>(0, (total, item) => total + item.price);
  }
}

List<ItemResultMonthGroup> groupItemResults({
  required List<Receipt> receipts,
  required Iterable<CategorisedItemView> items,
  Set<String>? includedReceiptIds,
}) {
  final receiptsById = <String, Receipt>{
    for (final receipt in receipts) receipt.id: receipt,
  };
  final itemsByReceiptId = <String, List<CategorisedItemView>>{};

  for (final item in items) {
    if (!receiptsById.containsKey(item.receiptId)) {
      continue;
    }
    itemsByReceiptId
        .putIfAbsent(item.receiptId, () => <CategorisedItemView>[])
        .add(item);
  }

  final receiptIds = includedReceiptIds == null
      ? itemsByReceiptId.keys.toSet()
      : includedReceiptIds.where(receiptsById.containsKey).toSet();
  final receiptGroups = receiptIds.map((receiptId) {
    final receiptItems =
        List<CategorisedItemView>.from(itemsByReceiptId[receiptId] ?? const [])
          ..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
    return ItemResultReceiptGroup(
      receipt: receiptsById[receiptId]!,
      items: receiptItems,
    );
  }).toList()
    ..sort((a, b) {
      final dateComparison = b.receipt.date.compareTo(a.receipt.date);
      if (dateComparison != 0) {
        return dateComparison;
      }
      return a.receipt.id.compareTo(b.receipt.id);
    });

  final receiptsByMonth = <DateTime, List<ItemResultReceiptGroup>>{};
  for (final receiptGroup in receiptGroups) {
    final receiptDate = receiptGroup.receipt.date;
    final monthKey = DateTime(receiptDate.year, receiptDate.month);
    receiptsByMonth
        .putIfAbsent(monthKey, () => <ItemResultReceiptGroup>[])
        .add(receiptGroup);
  }

  final monthGroups = receiptsByMonth.entries.map((entry) {
    return ItemResultMonthGroup(
      monthKey: entry.key,
      receipts: entry.value,
    );
  }).toList()
    ..sort((a, b) => b.monthKey.compareTo(a.monthKey));

  return monthGroups;
}
