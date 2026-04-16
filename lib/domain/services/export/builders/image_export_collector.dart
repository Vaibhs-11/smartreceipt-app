import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/services/export/export_file_namer.dart';

abstract class ExportReceiptFileResolver {
  const ExportReceiptFileResolver();

  Future<ResolvedExportReceiptFile?> resolve(Receipt receipt);
}

abstract class ResolvedExportReceiptFile {
  const ResolvedExportReceiptFile();

  String get sourcePath;
  String? get contentType;

  Future<void> writeTo(File destination);
}

class ImageExportCollector {
  const ImageExportCollector({
    required this.fileResolver,
    required this.fileNamer,
  });

  final ExportReceiptFileResolver fileResolver;
  final ExportFileNamer fileNamer;

  Future<ImageExportCollectionResult> collect({
    required List<Receipt> receipts,
    required Directory workingDirectory,
  }) async {
    final imagesDirectory = Directory(p.join(workingDirectory.path, 'images'));
    await imagesDirectory.create(recursive: true);

    final exportedFiles = <File>[];
    final skippedReceiptIds = <String>[];

    for (final receipt in receipts) {
      try {
        final source = await fileResolver.resolve(receipt);
        if (source == null) {
          skippedReceiptIds.add(receipt.id);
          continue;
        }

        final extension = _resolveExtension(source);
        final filename = fileNamer.buildReceiptFileName(
          receipt: receipt,
          extension: extension,
        );
        final outputFile = File(p.join(imagesDirectory.path, filename));
        await source.writeTo(outputFile);
        exportedFiles.add(outputFile);
      } catch (_) {
        skippedReceiptIds.add(receipt.id);
      }
    }

    return ImageExportCollectionResult(
      imageDirectory: imagesDirectory,
      exportedFiles: exportedFiles,
      skippedReceiptIds: skippedReceiptIds,
    );
  }

  String _resolveExtension(ResolvedExportReceiptFile source) {
    final sourceExtension = p
        .extension(Uri.parse(source.sourcePath).path)
        .replaceFirst('.', '')
        .trim()
        .toLowerCase();
    if (sourceExtension.isNotEmpty) {
      return sourceExtension;
    }

    final contentType = source.contentType?.toLowerCase() ?? '';
    if (contentType.contains('pdf')) return 'pdf';
    if (contentType.contains('png')) return 'png';
    if (contentType.contains('jpeg') || contentType.contains('jpg')) {
      return 'jpg';
    }
    return 'bin';
  }
}

class ImageExportCollectionResult {
  const ImageExportCollectionResult({
    required this.imageDirectory,
    required this.exportedFiles,
    required this.skippedReceiptIds,
  });

  final Directory imageDirectory;
  final List<File> exportedFiles;
  final List<String> skippedReceiptIds;
}
