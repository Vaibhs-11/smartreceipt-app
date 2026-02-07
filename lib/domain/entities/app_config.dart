import 'package:receiptnest/domain/exceptions/app_config_exception.dart';

class AppConfig {
  const AppConfig({
    required this.freeReceiptLimit,
    required this.premiumReceiptLimit,
    required this.enablePaidTiers,
  });

  final int freeReceiptLimit;
  final int premiumReceiptLimit;
  final bool enablePaidTiers;

  factory AppConfig.fromFirestore(Map<String, dynamic> data) {
    final freeLimitRaw = data['freeReceiptLimit'];
    if (freeLimitRaw == null) {
      throw const AppConfigUnavailableException(
        'Missing freeReceiptLimit in app config.',
      );
    }
    if (freeLimitRaw is! num) {
      throw const AppConfigUnavailableException(
        'Invalid freeReceiptLimit type in app config.',
      );
    }
    return AppConfig(
      freeReceiptLimit: freeLimitRaw.toInt(),
      premiumReceiptLimit: (data['premiumReceiptLimit'] as num?)?.toInt() ?? -1,
      enablePaidTiers: data['enablePaidTiers'] as bool? ?? true,
    );
  }
}
