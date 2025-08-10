import 'package:smartreceipt/domain/entities/receipt.dart';

abstract class ReceiptRepository {
  Future<List<Receipt>> getAllReceipts();
  Future<Receipt?> getReceiptById(String id);
  Future<void> addReceipt(Receipt receipt);
  Future<void> updateReceipt(Receipt receipt);
  Future<void> deleteReceipt(String id);
}


