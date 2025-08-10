import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

class GetReceiptsUseCase {
  const GetReceiptsUseCase(this._repository);
  final ReceiptRepository _repository;

  Future<List<Receipt>> call() => _repository.getAllReceipts();
}

final AutoDisposeProvider<GetReceiptsUseCase> getReceiptsUseCaseProvider =
    Provider.autoDispose<GetReceiptsUseCase>((ref) {
  final ReceiptRepository repository = ref.read(receiptRepositoryProvider);
  return GetReceiptsUseCase(repository);
});


