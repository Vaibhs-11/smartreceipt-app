import 'package:receiptnest/domain/repositories/account_repository.dart';

class DeleteAccountUseCase {
  DeleteAccountUseCase(this._repository);

  final AccountRepository _repository;

  Future<void> call() {
    return _repository.deleteAccount();
  }
}
