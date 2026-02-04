import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/repositories/receipt_repository.dart';
import 'package:receiptnest/presentation/providers/providers.dart'
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
