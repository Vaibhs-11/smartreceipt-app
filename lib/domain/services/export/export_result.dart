class ExportResult {
  const ExportResult({
    required this.zipPath,
    required this.fileName,
    required this.exportedFileCount,
    this.skippedReceiptIds = const <String>[],
  });

  final String zipPath;
  final String fileName;
  final int exportedFileCount;
  final List<String> skippedReceiptIds;

  bool get hasSkippedReceipts => skippedReceiptIds.isNotEmpty;
}
