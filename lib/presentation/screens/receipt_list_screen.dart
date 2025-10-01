import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';

/// StateProvider to hold current search query
final searchQueryProvider = StateProvider<String>((ref) => "");

class ReceiptListScreen extends ConsumerWidget {
  const ReceiptListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Receipt>> receipts = ref.watch(receiptsProvider);
    final searchQuery = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Receipts"),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await showSearch<String?>(
                context: context,
                delegate: ReceiptSearchDelegate(ref),
              );
              if (result != null) {
                ref.read(searchQueryProvider.notifier).state = result;
              }
            },
          ),
        ],
      ),
      body: receipts.when(
        data: (items) {
          // Filter receipts based on query
          final query = searchQuery.toLowerCase();
          final filtered = items.where((r) {
            if (query.isEmpty) return true;
            final matchStore = r.storeName.toLowerCase().contains(query);
            final matchDate = r.date.toIso8601String().contains(query);
            final matchTax = query == "tax" &&
                r.items.any((i) => i.taxClaimable); // match if any item is tax claimable
            return matchStore || matchDate || matchTax;
          }).toList();

          if (filtered.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final receipt = filtered[index];
              return Dismissible(
                key: ValueKey(receipt.id),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                direction: DismissDirection.startToEnd,
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Delete Receipt"),
                          content: const Text(
                              "Are you sure you want to delete this receipt?"),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("Cancel")),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text("Delete")),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) {
                  ref.read(receiptsProvider.notifier).deleteReceipt(receipt.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Receipt deleted")),
                  );
                },
                child: ListTile(
                  title: Text(receipt.storeName),
                  subtitle: Text(receipt.date.toIso8601String()),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Delete Receipt"),
                          content: const Text(
                              "Are you sure you want to delete this receipt?"),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("Cancel")),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text("Delete")),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        ref
                            .read(receiptsProvider.notifier)
                            .deleteReceipt(receipt.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Receipt deleted")),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          );
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

/// SearchDelegate for searching receipts
class ReceiptSearchDelegate extends SearchDelegate<String?> {
  final WidgetRef ref;
  ReceiptSearchDelegate(this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = "",
        )
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) {
    close(context, query);
    return Container();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Center(
      child: Text("Search by store, date, or 'tax'"),
    );
  }
}
