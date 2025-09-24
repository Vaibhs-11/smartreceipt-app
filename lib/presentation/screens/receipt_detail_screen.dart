import 'dart:io';
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

          final currencyFormatter =
              NumberFormat.currency(symbol: receipt.currency);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // --- Optional receipt image/file ---
                if (receipt.fileUrl != null && receipt.fileUrl!.isNotEmpty) ...[
                  if (receipt.fileUrl!.toLowerCase().endsWith('.jpg') ||
                      receipt.fileUrl!.toLowerCase().endsWith('.jpeg') ||
                      receipt.fileUrl!.toLowerCase().endsWith('.png') ||
                      receipt.fileUrl!.toLowerCase().endsWith('.gif') ||
                      receipt.fileUrl!.toLowerCase().endsWith('.webp'))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        receipt.fileUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Text("Could not load image"),
                      ),
                    )
                  else if (receipt.fileUrl!.toLowerCase().endsWith('.pdf'))
                    ListTile(
                      leading:
                          const Icon(Icons.picture_as_pdf, color: Colors.red),
                      title: const Text("Receipt PDF"),
                      subtitle: Text(receipt.storeName),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("PDF viewing not yet implemented")),
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                ] else if (receipt.imagePath != null &&
                    receipt.imagePath!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(receipt.imagePath!),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // --- Store name & details ---
                Text(
                  receipt.storeName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(DateFormat.yMMMMd().format(receipt.date)),
                const SizedBox(height: 8),
                Text(
                  currencyFormatter.format(receipt.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                // --- Itemized purchases ---
                if (receipt.items.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Items',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: receipt.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = receipt.items[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.name),
                        trailing: Text(
                          currencyFormatter.format(item.price),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      );
                    },
                  ),
                ],

                // --- Notes ---
                if (receipt.notes != null &&
                    receipt.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Notes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
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
