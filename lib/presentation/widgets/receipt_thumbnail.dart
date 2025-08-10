import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';

class ReceiptThumbnail extends StatelessWidget {
  const ReceiptThumbnail({super.key, required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: <Widget>[
            const Icon(Icons.receipt_long, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(receipt.storeName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateFormat.yMMMd().format(receipt.date)),
                ],
              ),
            ),
            Text('${receipt.currency} ${receipt.total.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}


