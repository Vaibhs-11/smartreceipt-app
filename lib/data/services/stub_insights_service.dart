import 'package:flutter/foundation.dart';
import 'package:receiptnest/domain/models/receipt_filter.dart';
import 'package:receiptnest/domain/services/insights_service.dart';

class StubInsightsService implements InsightsService {
  const StubInsightsService();

  @override
  Future<InsightsResult> generateInsights({
    List<String>? receiptIds,
    ReceiptFilter? filter,
    InsightsGroupBy groupBy = InsightsGroupBy.category,
  }) async {
    debugPrint(
      'StubInsightsService.generateInsights called. '
      'receiptCount=${receiptIds?.length ?? 0} '
      'filter=$filter',
    );

    return InsightsResult(
      receiptIds: List<String>.unmodifiable(receiptIds ?? const <String>[]),
      groupBy: groupBy,
      generatedAt: DateTime.now().toUtc(),
      isSuccess: false,
      message: 'InsightsService is not implemented yet.',
    );
  }
}
