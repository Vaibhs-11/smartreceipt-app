import '../entities/receipt.dart';
import '../models/categorised_item_view.dart';

List<CategorisedItemView> buildItemIndex(List<Receipt> receipts) {
  final List<CategorisedItemView> index = [];

  for (final receipt in receipts) {
    for (var i = 0; i < receipt.items.length; i++) {
      final item = receipt.items[i];
      index.add(
        CategorisedItemView(
          receiptId: receipt.id,
          itemIndex: i,
          itemName: item.name,
          price: item.price ?? 0.0,
          merchant: receipt.storeName,
          date: receipt.date,
          category: item.category,
        ),
      );
    }
  }

  return index;
}
