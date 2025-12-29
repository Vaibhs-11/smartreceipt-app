class AppConfig {
  const AppConfig({
    this.freeReceiptLimit = 10,
    this.premiumReceiptLimit = -1,
    this.enablePaidTiers = true,
  });

  final int freeReceiptLimit;
  final int premiumReceiptLimit;
  final bool enablePaidTiers;

  factory AppConfig.fromFirestore(Map<String, dynamic> data) {
    return AppConfig(
      freeReceiptLimit: (data['freeReceiptLimit'] as num?)?.toInt() ?? 10,
      premiumReceiptLimit: (data['premiumReceiptLimit'] as num?)?.toInt() ?? -1,
      enablePaidTiers: data['enablePaidTiers'] as bool? ?? true,
    );
  }
}
