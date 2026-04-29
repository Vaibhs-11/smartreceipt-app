import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/core/constants/app_constants.dart';

void main() {
  test('supported currencies include NZD and Other', () {
    expect(AppConstants.supportedCurrencies, contains('NZD'));
    expect(
      AppConstants.supportedCurrencies,
      contains(AppConstants.otherCurrency),
    );
  });

  test('sortCurrencyOptions keeps Other as the final option', () {
    final sorted = AppConstants.sortCurrencyOptions(<String>[
      'USD',
      AppConstants.otherCurrency,
      'AUD',
      'NZD',
    ]);

    expect(sorted, <String>['AUD', 'NZD', 'USD', AppConstants.otherCurrency]);
  });
}
