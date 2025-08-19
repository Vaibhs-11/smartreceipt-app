import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/widgets/receipt_list.dart';

class ReceiptListScreen extends ConsumerWidget {
  const ReceiptListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<dynamic>> receipts = ref.watch(receiptsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Receipts"),
      ),
      body: receipts.when(
          data: (data) {
          final items = data.cast<Receipt>();
      return items.isEmpty
          ? const _EmptyState()
          : ReceiptList(receipts: items);
    },
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, st) => Center(child: Text('Error: $e')),
    ),
  );

  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            Icon(Icons.receipt_long, size: 64),
            SizedBox(height: 12),
            Text('No receipts yet'),
            SizedBox(height: 8),
            Text('Add a receipt manually or scan one with OCR.'),
          ],
        ),
      ),
    );
  }
}
