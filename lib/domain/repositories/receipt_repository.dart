import 'package:receiptnest/domain/entities/receipt.dart';

abstract class ReceiptRepository {
  Future<List<Receipt>> getReceipts();
  Future<Receipt?> getReceiptById(String id);
  Future<int> getReceiptCount();
  Future<void> addReceipt(Receipt receipt);
  Future<void> updateReceipt(Receipt receipt);
  Future<void> deleteReceipt(String id);
}

