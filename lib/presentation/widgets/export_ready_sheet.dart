import 'package:flutter/material.dart';

enum ExportReadyAction { save, share }

Future<ExportReadyAction?> showExportReadySheet(
  BuildContext context, {
  required int skippedReceiptCount,
  int? debugBytesLength,
}) {
  return showModalBottomSheet<ExportReadyAction>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final description = skippedReceiptCount > 0
          ? 'Your export is ready. $skippedReceiptCount receipts were skipped because they could not be included.'
          : 'Your export is ready. Save it to your device or share it now.';

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export ready',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(ExportReadyAction.save),
                  child: const Text('Save to device'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(ExportReadyAction.share),
                  child: const Text('Share'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
