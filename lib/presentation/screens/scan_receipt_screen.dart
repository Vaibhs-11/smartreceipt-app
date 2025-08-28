import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';

class ScanReceiptScreen extends ConsumerWidget {
  const ScanReceiptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OcrService ocr = ref.read(ocrServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receipt')),
      body: Center(
        child: FilledButton.icon(
          onPressed: () async {
            final OcrResult result = await ocr.parseImage('demo/path/image_${DateTime.now().millisecondsSinceEpoch}.jpg');
            showDialog<void>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: const Text('OCR Result (stub)'),
                content: Text(
                  'Store: ${result.storeName}\nDate: ${result.date != null ? DateFormat.yMMMd().format(result.date!) : '-'}\nTotal: ${result.total?.toStringAsFixed(2) ?? '-'}',
                ),
                actions: <Widget>[
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ],
              ),
            );
          },
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Simulate Scan'),
        ),
      ),
    );
  }
}
