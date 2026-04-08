import 'package:receiptnest/domain/models/receipt_filter.dart';

enum InsightsGroupBy { category, merchant, date }

class InsightMetric {
  const InsightMetric({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final double value;
}

class InsightsResult {
  const InsightsResult({
    required this.receiptIds,
    required this.groupBy,
    this.metrics = const <InsightMetric>[],
    this.generatedAt,
    this.isSuccess = true,
    this.message,
  });

  final List<String> receiptIds;
  final InsightsGroupBy groupBy;
  final List<InsightMetric> metrics;
  final DateTime? generatedAt;
  final bool isSuccess;
  final String? message;
}

abstract class InsightsService {
  Future<InsightsResult> generateInsights({
    List<String>? receiptIds,
    ReceiptFilter? filter,
    InsightsGroupBy groupBy = InsightsGroupBy.category,
  });
}
