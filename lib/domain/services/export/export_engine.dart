import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/services/export/builders/image_export_collector.dart';
import 'package:receiptnest/domain/services/export/builders/reimbursement_csv_builder.dart';
import 'package:receiptnest/domain/services/export/builders/reimbursement_pdf_builder.dart';
import 'package:receiptnest/domain/services/export/builders/tax_items_csv_builder.dart';
import 'package:receiptnest/domain/services/export/builders/zip_export_builder.dart';
import 'package:receiptnest/domain/services/export/export_context.dart';
import 'package:receiptnest/domain/services/export/export_exception.dart';
import 'package:receiptnest/domain/services/export/export_file_namer.dart';
import 'package:receiptnest/domain/services/export/export_result.dart';

abstract class ExportEngine {
  Future<ExportResult> generate({
    required List<Receipt> receipts,
    required ExportContext context,
  });
}

abstract class ExportWorkingDirectoryProvider {
  const ExportWorkingDirectoryProvider();

  Future<Directory> createWorkingDirectory(ExportContext context);
}

class OnDeviceExportEngine implements ExportEngine {
  const OnDeviceExportEngine({
    required this.workingDirectoryProvider,
    required this.imageExportCollector,
    this.csvBuilder = const ReimbursementCsvBuilder(),
    this.taxItemsCsvBuilder = const TaxItemsCsvBuilder(),
    this.pdfBuilder = const ReimbursementPdfBuilder(),
    this.zipBuilder = const ZipExportBuilder(),
    this.fileNamer = const ExportFileNamer(),
    this.clock,
  });

  final ExportWorkingDirectoryProvider workingDirectoryProvider;
  final ImageExportCollector imageExportCollector;
  final ReimbursementCsvBuilder csvBuilder;
  final TaxItemsCsvBuilder taxItemsCsvBuilder;
  final ReimbursementPdfBuilder pdfBuilder;
  final ZipExportBuilder zipBuilder;
  final ExportFileNamer fileNamer;
  final DateTime Function()? clock;

  @override
  Future<ExportResult> generate({
    required List<Receipt> receipts,
    required ExportContext context,
  }) async {
    if (receipts.isEmpty) {
      throw const ExportException('No receipts available for export.');
    }

    final workingDirectory =
        await workingDirectoryProvider.createWorkingDirectory(context);
    final imageResult = await imageExportCollector.collect(
      receipts: receipts,
      workingDirectory: workingDirectory,
    );

    if (imageResult.exportedFiles.isEmpty) {
      throw const ExportException('No exportable receipt files were found.');
    }

    final timestamp = (clock ?? DateTime.now).call();
    final zipFileName = fileNamer.buildArchiveFileName(
      title: context.title,
      label: context.source == ExportSource.collection
          ? 'reimbursement_export'
          : 'tax_evidence_export',
      timestamp: timestamp,
    );
    final exportFolderName = p.basenameWithoutExtension(zipFileName);

    final zipEntries = <ZipEntryFile>[];

    if (context.source == ExportSource.collection) {
      final pdfFile = await pdfBuilder.build(
        receipts: receipts,
        context: context,
        directory: workingDirectory,
      );
      final csvFile = await csvBuilder.build(
        receipts: receipts,
        directory: workingDirectory,
      );
      zipEntries.insert(
        0,
        ZipEntryFile(
          file: csvFile,
          archivePath: p.join(exportFolderName, 'receipts.csv'),
        ),
      );
      zipEntries.insert(
        0,
        ZipEntryFile(
          file: pdfFile,
          archivePath: p.join(exportFolderName, 'report.pdf'),
        ),
      );
    } else {
      final taxItemsCsvFile = await taxItemsCsvBuilder.build(
        receipts: receipts,
        directory: workingDirectory,
      );
      zipEntries.add(
        ZipEntryFile(
          file: taxItemsCsvFile,
          archivePath: p.join(exportFolderName, 'Tax_Items.csv'),
        ),
      );
    }

    zipEntries.addAll(
      <ZipEntryFile>[
        for (final file in imageResult.exportedFiles)
          ZipEntryFile(
            file: file,
            archivePath: p.join(exportFolderName, p.basename(file.path)),
          ),
      ],
    );

    final zipFile = await zipBuilder.build(
      outputPath: p.join(workingDirectory.path, zipFileName),
      files: zipEntries,
    );

    return ExportResult(
      zipPath: zipFile.path,
      fileName: zipFileName,
      exportedFileCount: imageResult.exportedFiles.length,
      skippedReceiptIds: imageResult.skippedReceiptIds,
    );
  }
}
