import 'dart:typed_data';

class ExportResult {
  const ExportResult({
    required this.zipPath,
    required this.fileName,
    required this.exportedFileCount,
    this.skippedReceiptIds = const <String>[],
    this.savedPath,
    this.fileBytes,
  });

  final String zipPath;
  final String fileName;
  final int exportedFileCount;
  final List<String> skippedReceiptIds;
  final String? savedPath;
  final Uint8List? fileBytes;

  bool get hasSkippedReceipts => skippedReceiptIds.isNotEmpty;
}
