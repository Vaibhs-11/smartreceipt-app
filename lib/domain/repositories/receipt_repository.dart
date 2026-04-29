import 'package:receiptnest/domain/entities/receipt.dart';

abstract class ReceiptRepository {
  Future<List<Receipt>> getReceipts();
  Future<Receipt?> getReceiptById(String id);
  Future<int> getReceiptCount();
  Future<void> addReceipt(Receipt receipt);
  Future<void> updateReceipt(Receipt receipt);
  Future<void> deleteReceipt(String id);
  Future<void> assignReceiptsToCollection(
    List<String> receiptIds,
    String collectionId,
  );
  Future<void> removeReceiptFromCollection(String receiptId);
  Future<void> removeReceiptsFromCollection(List<String> receiptIds);
  Future<void> moveReceiptToCollection(
    String receiptId,
    String newCollectionId,
  );
}
