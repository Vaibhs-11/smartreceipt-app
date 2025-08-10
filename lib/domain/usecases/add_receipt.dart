import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

class AddReceiptUseCase {
  const AddReceiptUseCase(this._repository);
  final ReceiptRepository _repository;

  Future<void> call(Receipt receipt) => _repository.addReceipt(receipt);
}

final AutoDisposeProvider<AddReceiptUseCase> addReceiptUseCaseProvider =
    Provider.autoDispose<AddReceiptUseCase>((ref) {
  final ReceiptRepository repository = ref.read(receiptRepositoryProvider);
  return AddReceiptUseCase(repository);
});

final Provider<ReceiptRepository> receiptRepositoryProvider =
    Provider<ReceiptRepository>((ref) {
  throw UnimplementedError('receiptRepositoryProvider must be overridden');
});


