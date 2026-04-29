// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:receiptnest/core/utils/app_logger.dart';
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

  Future<ExportResult> prepareExport({
    required List<Receipt> receipts,
    required ExportContext context,
  }) async {
    final result = await exportEngine.generate(
      receipts: receipts,
      context: context,
    );
    final file = File(result.zipPath);
    if (!await file.exists()) {
      throw Exception('Export file not found at ${result.zipPath}');
    }

    final fileBytes = await file.readAsBytes();
    if (fileBytes.isEmpty) {
      throw Exception('Export file is empty');
    }

    AppLogger.log('Export ready');

    return ExportResult(
      zipPath: result.zipPath,
      fileName: result.fileName,
      exportedFileCount: result.exportedFileCount,
      skippedReceiptIds: result.skippedReceiptIds,
      fileBytes: fileBytes,
    );
  }

  Future<void> shareExport({
    required ExportResult result,
    required BuildContext? shareContext,
  }) {
    return shareLauncher.share(
      filePath: result.zipPath,
      fileName: result.fileName,
      context: shareContext,
    );
  }

  Future<String?> saveExportToDevice({
    required ExportResult result,
  }) async {
    if (result.fileBytes == null || result.fileBytes!.isEmpty) {
      throw Exception('Export data missing');
    }

    final fileName = result.fileName.isNotEmpty
        ? result.fileName
        : 'receipt_export_${DateTime.now().millisecondsSinceEpoch}.zip';
    AppLogger.log('Saving export');
    final savedPath = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: result.fileBytes!,
        fileName: fileName,
        mimeTypesFilter: <String>['application/zip'],
      ),
    );

    if (savedPath == null) {
      return null;
    }
    AppLogger.log('Export saved');

    return savedPath;
  }

  Future<ExportResult> exportAndShare({
    required List<Receipt> receipts,
    required ExportContext context,
    required BuildContext? shareContext,
  }) async {
    final result = await prepareExport(
      receipts: receipts,
      context: context,
    );
    await shareExport(
      result: result,
      shareContext: shareContext,
    );
    return result;
  }
}
