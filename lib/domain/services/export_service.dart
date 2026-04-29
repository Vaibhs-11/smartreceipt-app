import 'package:receiptnest/domain/models/receipt_filter.dart';

enum ExportFormat { pdf, zip }

enum ExportContextType { trip, tax, downgrade, custom }

class ExportContext {
  const ExportContext({
    required this.type,
    this.name,
    this.sourceId,
  });

  final ExportContextType type;
  final String? name;
  final String? sourceId;
}

class ExportResult {
  const ExportResult({
    required this.format,
    required this.receiptIds,
    this.filePath,
    this.generatedAt,
    this.isSuccess = true,
    this.message,
  });

  final ExportFormat format;
  final List<String> receiptIds;
  final String? filePath;
  final DateTime? generatedAt;
  final bool isSuccess;
  final String? message;
}

abstract class ExportService {
  Future<ExportResult> exportReceipts({
    required String userId,
    List<String>? receiptIds,
    ReceiptFilter? filter,
    required ExportFormat format,
    ExportContext? context,
  });
}
