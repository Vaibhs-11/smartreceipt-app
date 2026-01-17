import 'package:smartreceipt/domain/entities/app_config.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/policies/account_policies.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';
import 'package:smartreceipt/domain/repositories/user_repository.dart';

class AddReceiptUseCase {
  const AddReceiptUseCase(
    this._receiptRepository,
    this._userRepository,
    this._appConfigReader,
  );
  final ReceiptRepository _receiptRepository;
  final UserRepository _userRepository;
  final Future<AppConfig> Function() _appConfigReader;

  Future<void> call(Receipt receipt) async {
    final profile = await _userRepository.getCurrentUserProfile();
    if (profile == null) return;

    final appConfig = await _appConfigReader();
    final receiptCount = await _receiptRepository.getReceiptCount();
    final now = DateTime.now().toUtc();

    final allowed =
        AccountPolicies.canAddReceipt(profile, receiptCount, now, appConfig);
    if (!allowed) {
      throw StateError('Receipt limit reached');
    }

    return _receiptRepository.addReceipt(receipt);
  }
}
