import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';

class ReceiptDetailScreen extends StatelessWidget {
  const ReceiptDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Object? args = ModalRoute.of(context)?.settings.arguments;
    final Receipt receipt = (args is Receipt)
        ? args
        : Receipt(
            id: 'unknown', storeName: 'Unknown', date: DateTime.now(), total: 0, currency: 'USD');

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Detail')),
      body: Padding(
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
            if (receipt.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              const Text('Tags', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 8, children: receipt.tags.map((String t) => Chip(label: Text(t))).toList()),
            ],
          ],
        ),
      ),
    );
  }
}


