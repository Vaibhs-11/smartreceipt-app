import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';

class ReceiptDetailScreen extends ConsumerWidget {
  final String receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(receiptDetailProvider(receiptId));

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Detail')),
      body: receiptAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (receipt) {
          if (receipt == null) {
            return const Center(child: Text('Receipt not found.'));
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(receipt.storeName, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(DateFormat.yMMMMd().format(receipt.date)),
                const SizedBox(height: 8),
                Text('${receipt.currency} ${receipt.total.toStringAsFixed(2)}'),
                if (receipt.notes != null) ...<Widget>[
                  const SizedBox(height: 16),
                  const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(receipt.notes!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
