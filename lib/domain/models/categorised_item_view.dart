class CategorisedItemView {
  final String receiptId;
  final int itemIndex;
  final String itemName;
  final double price;
  final String merchant;
  final DateTime date;
  final String? category;
  final bool taxClaimable;

  const CategorisedItemView({
    required this.receiptId,
    required this.itemIndex,
    required this.itemName,
    required this.price,
    required this.merchant,
    required this.date,
    required this.category,
    required this.taxClaimable,
  });
}
