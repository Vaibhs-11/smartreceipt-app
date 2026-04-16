import 'dart:io';

import 'package:archive/archive_io.dart';

class ZipExportBuilder {
  const ZipExportBuilder();

  Future<File> build({
    required String outputPath,
    required List<ZipEntryFile> files,
  }) async {
    final encoder = ZipFileEncoder();
    encoder.create(outputPath);
    try {
      for (final file in files) {
        await encoder.addFile(file.file, file.archivePath);
      }
    } finally {
      encoder.close();
    }
    return File(outputPath);
  }
}

class ZipEntryFile {
  const ZipEntryFile({
    required this.file,
    required this.archivePath,
  });

  final File file;
  final String archivePath;
}
