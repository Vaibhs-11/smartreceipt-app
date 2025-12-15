import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';
import 'package:smartreceipt/presentation/providers/providers.dart'
    show receiptRepositoryProviderOverride;

class GetReceiptsUseCase {
  const GetReceiptsUseCase(this._repository);
  final ReceiptRepository _repository;

  Future<List<Receipt>> call() => _repository.getReceipts();
}

final AutoDisposeProvider<GetReceiptsUseCase> getReceiptsUseCaseProviderOverride =
    Provider.autoDispose<GetReceiptsUseCase>((ref) {
  final ReceiptRepository repository =
      ref.read(receiptRepositoryProviderOverride);
  return GetReceiptsUseCase(repository);
});
