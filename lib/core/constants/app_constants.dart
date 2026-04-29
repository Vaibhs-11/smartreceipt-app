class AppConstants {
  static const String appName = 'ReceiptNest';
  static const String otherCurrency = 'Other';

  static const List<String> supportedCurrencies = <String>[
    'USD',
    'EUR',
    'GBP',
    'INR',
    'JPY',
    'AUD',
    'CAD',
    'CHF',
    'CNY',
    'SGD',
    'NZD',
    otherCurrency,
  ];

  static List<String> sortCurrencyOptions(Iterable<String> options) {
    final sorted = options.toSet().toList()
      ..sort((left, right) {
        if (left == otherCurrency) return 1;
        if (right == otherCurrency) return -1;
        return left.compareTo(right);
      });
    return sorted;
  }
}
