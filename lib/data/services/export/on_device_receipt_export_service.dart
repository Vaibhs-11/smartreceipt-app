// ignore_for_file: use_build_context_synchronously

import 'package:flutter/widgets.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/services/export/export_context.dart';
import 'package:receiptnest/domain/services/export/export_engine.dart';
import 'package:receiptnest/domain/services/export/export_result.dart';

abstract class ExportShareLauncher {
  const ExportShareLauncher();

  Future<void> share({
    required String filePath,
    required String fileName,
    required BuildContext? context,
  });
}

class OnDeviceReceiptExportService {
  const OnDeviceReceiptExportService({
    required this.exportEngine,
    required this.shareLauncher,
  });

  final ExportEngine exportEngine;
  final ExportShareLauncher shareLauncher;

  Future<ExportResult> exportAndShare({
    required List<Receipt> receipts,
    required ExportContext context,
    required BuildContext? shareContext,
  }) async {
    final result = await exportEngine.generate(
      receipts: receipts,
      context: context,
    );
    await shareLauncher.share(
      filePath: result.zipPath,
      fileName: result.fileName,
      context: shareContext,
    );
    return result;
  }
}
