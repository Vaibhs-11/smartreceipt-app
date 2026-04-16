import 'dart:convert';
import 'dart:io';

import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/services/insights_engine.dart';

class ReimbursementCsvBuilder {
  const ReimbursementCsvBuilder({
    this.insightsEngine = const InsightsEngine(),
  });

  final InsightsEngine insightsEngine;

  Future<File> build({
    required List<Receipt> receipts,
    required Directory directory,
  }) async {
    final csvFile = File('${directory.path}/receipts.csv');
    final rows = <List<String>>[
      const <String>[
        'Date',
        'Merchant',
        'Item',
        'Category',
        'Amount',
        'Currency',
      ],
    ];

    final sortedReceipts = List<Receipt>.from(receipts)
      ..sort((a, b) => a.date.compareTo(b.date));

    for (final receipt in sortedReceipts) {
      for (final item in receipt.items) {
        final amount = item.price;
        final itemName = item.name.trim();
        if (amount == null || amount <= 0 || itemName.isEmpty) {
          continue;
        }

        rows.add(
          <String>[
            _dateLabel(receipt.date),
            receipt.storeName.trim(),
            itemName,
            insightsEngine.resolveEffectiveCategory(
              item: item,
              isCollectionQuery: true,
            ),
            amount.toStringAsFixed(2),
            _normalizeCurrency(receipt.currency),
          ],
        );
      }
    }

    final csv = rows.map(_encodeRow).join('\n');
    return csvFile.writeAsString('$csv\n', encoding: utf8);
  }

  String _encodeRow(List<String> columns) {
    return columns.map(_escapeColumn).join(',');
  }

  String _escapeColumn(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _dateLabel(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _normalizeCurrency(String currency) {
    final normalized = currency.trim();
    return normalized.isEmpty ? 'Unknown' : normalized;
  }
}
