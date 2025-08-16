import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/receipt_list_screen.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthService auth = ref.watch(authServiceProvider);
    return StreamBuilder<AppUser?>(
      stream: auth.authStateChanges(),
      builder: (BuildContext context, AsyncSnapshot<AppUser?> snapshot) {
        final bool isAuthed = snapshot.data != null;
        if (!isAuthed) {
          return Scaffold(
            appBar: AppBar(title: const Text('SmartReceipt')),
            body: Center(
              child: FilledButton(
                onPressed: () => auth.signInAnonymously(),
                child: const Text('Continue without account'),
              ),
            ),
          );
        }
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
      },
    );
  }
}


