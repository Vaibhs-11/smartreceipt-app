import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

class GetReceiptByIdUseCase {
  const GetReceiptByIdUseCase(this._repository);
  final ReceiptRepository _repository;

  Future<Receipt?> call(String id) => _repository.getReceiptById(id);
}