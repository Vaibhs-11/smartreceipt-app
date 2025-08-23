import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/receipt_list_screen.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AuthGate ensures this screen is only shown when authenticated.
    // We use `ref.read` as we only need the service for the signOut callback.
    final auth = ref.read(authServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipts'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.scanReceipt),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
            tooltip: 'Sign out',
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
