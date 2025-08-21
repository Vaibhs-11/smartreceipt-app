import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';

class ReceiptList extends StatelessWidget {
  final List<Receipt> receipts;

  const ReceiptList({super.key, required this.receipts});
  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) {
      return const Center(child: Text("No receipts found."));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: receipts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Receipt r = receipts[index];
        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 16,
            ),
            title: Text(
              r.storeName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${DateFormat.yMMMd().format(r.date)} • ${r.currency} ${r.total.toStringAsFixed(2)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.receiptDetail,
              arguments: r,
            ),
          ),
        );
      },
    );
  }
}
