import 'package:flutter/material.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/receipt_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipts'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.scanReceipt),
          ),
        ],
      ),
      body: const ReceiptListScreen(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.addReceipt),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}


