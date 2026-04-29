import 'package:receiptnest/core/utils/app_logger.dart';
import 'package:receiptnest/domain/models/receipt_filter.dart';
import 'package:receiptnest/domain/services/export_service.dart';

class StubExportService implements ExportService {
  const StubExportService();

  @override
  Future<ExportResult> exportReceipts({
    required String userId,
    List<String>? receiptIds,
    ReceiptFilter? filter,
    required ExportFormat format,
    ExportContext? context,
  }) async {
    AppLogger.log(
      'StubExportService.exportReceipts called. '
      'userId=$userId format=$format '
      'receiptCount=${receiptIds?.length ?? 0} '
      'filter=$filter',
    );

    return ExportResult(
      format: format,
      receiptIds: List<String>.unmodifiable(receiptIds ?? const <String>[]),
      generatedAt: DateTime.now().toUtc(),
      isSuccess: false,
      message: 'ExportService is not implemented yet.',
    );
  }
}
