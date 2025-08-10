import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';

class ReceiptListScreen extends ConsumerWidget {
  const ReceiptListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<dynamic>> receipts = ref.watch(receiptsProvider);
    return receipts.when(
      data: (List<dynamic> data) {
        final List<Receipt> items = data.cast<Receipt>();
        if (items.isEmpty) {
          return const _EmptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemBuilder: (BuildContext context, int index) {
            final Receipt r = items[index];
            return ListTile(
              title: Text(r.storeName),
              subtitle: Text('${DateFormat.yMMMd().format(r.date)} • ${r.currency} ${r.total.toStringAsFixed(2)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.receiptDetail, arguments: r),
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: items.length,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) => Center(child: Text('Error: $e')),
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
          children: <Widget>[
            const Icon(Icons.receipt_long, size: 64),
            const SizedBox(height: 12),
            const Text('No receipts yet'),
            const SizedBox(height: 8),
            const Text('Add a receipt manually or scan one with OCR.'),
          ],
        ),
      ),
    );
  }
}


