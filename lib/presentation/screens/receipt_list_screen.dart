import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';

/// StateProvider to hold current search query (including multiple filters)
final searchQueryProvider = StateProvider<String>((ref) => "");

class ReceiptListScreen extends ConsumerWidget {
  const ReceiptListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final isSearching = searchQuery.trim().isNotEmpty;

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
              if (result != null && result.isNotEmpty) {
                ref.read(searchQueryProvider.notifier).state = result;
              }
            },
          ),
        ],
      ),
      body: receiptsAsync.when(
        data: (receipts) {
          // Multiple filters support: "store:woolworths+date:2024"
          final filters = searchQuery
              .split("+")
              .where((q) => q.trim().isNotEmpty)
              .map((q) => q.split(":"))
              .toList();

          final filtered = receipts.where((r) {
            if (filters.isEmpty) return true;

            bool matchAll = true;
            for (final f in filters) {
              if (f.length < 2) continue;
              final key = f[0].trim().toLowerCase();
              final query = f[1].trim().toLowerCase();

              bool matches = false;
              switch (key) {
                case "store":
                  matches = r.storeName.toLowerCase().contains(query);
                  break;
                case "date":
                  matches = DateFormat.yMMMd()
                      .format(r.date)
                      .toLowerCase()
                      .contains(query);
                  break;
                case "product":
                  matches = r.items
                      .any((i) => i.name.toLowerCase().contains(query));
                  break;
                case "total":
                  matches = r.total
                      .toStringAsFixed(2)
                      .toLowerCase()
                      .contains(query);
                  break;
                case "tax claimable":
                  final normalized = query.toLowerCase();
                  final bool anyTaxClaimable =
                      r.items.any((i) => i.taxClaimable);
                  if (normalized == "true" ||
                      normalized == "yes" ||
                      normalized == "1") {
                    matches = anyTaxClaimable;
                  } else if (normalized == "false" ||
                      normalized == "no" ||
                      normalized == "0") {
                    matches = !anyTaxClaimable;
                  } else {
                    matches = false;
                  }
                  break;
              }

              if (!matches) matchAll = false;
            }

            return matchAll;
          }).toList();

          if (filtered.isEmpty) {
            return _NoResultsState(
              onBackPressed: () {
                ref.read(searchQueryProvider.notifier).state = "";
              },
            );
          }

          return Stack(
            children: [
              ListView.builder(
                padding: const EdgeInsets.all(12),
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
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text("Cancel")),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    child: const Text("Delete")),
                              ],
                            ),
                          ) ??
                          false;
                    },
                    onDismissed: (_) async {
                      await ref
                          .read(receiptRepositoryProviderOverride)
                          .deleteReceipt(receipt.id);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Receipt deleted")),
                      );
                    },

                    child: Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/receiptDetail',
                            arguments: receipt.id,
                          );
                        },
                        title: Text(
                          receipt.storeName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          DateFormat.yMMMd().format(receipt.date),
                        ),
                        trailing: Builder(
                          builder: (_) {
                            String formattedAmount;
                            try {
                              formattedAmount = NumberFormat.simpleCurrency(
                                      name: receipt.currency)
                                  .format(receipt.total);
                            } catch (_) {
                              formattedAmount =
                                  '${receipt.currency} ${receipt.total.toStringAsFixed(2)}';
                            }
                            return Text(
                              formattedAmount,
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Clear Search FAB (only visible when searching)
              if (isSearching)
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FloatingActionButton.extended(
                        heroTag: "clearSearchFab",
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                        onPressed: () {
                          ref.read(searchQueryProvider.notifier).state = "";
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text("Clear Search"),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),

      // Hide Add FAB when searching
      floatingActionButton:
          isSearching ? null : _AddReceiptFab(onPressed: () => Navigator.pushNamed(context, '/addReceipt')),
    );
  }
}

class _AddReceiptFab extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddReceiptFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: "addReceiptFab",
      onPressed: onPressed,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }
}

/// Shown when no search results are found
class _NoResultsState extends StatelessWidget {
  final VoidCallback onBackPressed;
  const _NoResultsState({required this.onBackPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No results found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Receipts'),
              onPressed: onBackPressed,
            ),
          ],
        ),
      ),
    );
  }
}

/// Enhanced SearchDelegate with visible dropdown & multiple filters
class ReceiptSearchDelegate extends SearchDelegate<String?> {
  final WidgetRef ref;
  ReceiptSearchDelegate(this.ref);

  String selectedFilter = "store";
  String _taxClaimableSelection = 'true';
  final List<String> filters = [
    "store",
    "date",
    "product",
    "total",
    "tax claimable",
  ];

  final List<Map<String, String>> filterConditions = [];

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: base.colorScheme.surface,
        foregroundColor: base.colorScheme.onSurface,
        elevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: base.colorScheme.onSurfaceVariant),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        // Clear field
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = "",
        ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) {
    // Combine filters into a single string like "store:coles+date:2024"
    final filtersCombined = [
      ...filterConditions.map((f) => "${f['key']}:${f['value']}"),
      if (query.isNotEmpty) "$selectedFilter:$query"
    ].where((q) => q.isNotEmpty).join("+");

    Future.microtask(() => close(context, filtersCombined));
    return const SizedBox.shrink();
  }

 @override
Widget buildSuggestions(BuildContext context) {
  return StatefulBuilder(
    builder: (context, setState) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true, // Prevents overflow on long filter names
                    value: selectedFilter,
                    decoration: InputDecoration(
                      labelText: "Filter",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    ),
                    items: filters
                        .map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: Text(f.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          selectedFilter = v;
                          if (selectedFilter == "tax claimable") {
                            query = _taxClaimableSelection;
                          } else {
                            query = "";
                          }
                        });
                      }
                    },
                  ),
                ),   // ✅ THIS BRACKET WAS MISSING EARLIER

                const SizedBox(width: 8),

                Expanded(
                  flex: 5,
                  child: selectedFilter == "tax claimable"
                      ? DropdownButtonFormField<String>(
                          value: _taxClaimableSelection,
                          decoration: const InputDecoration(
                            labelText: "Tax Claimable?",
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'true',
                              child: Text('Yes'),
                            ),
                            DropdownMenuItem(
                              value: 'false',
                              child: Text('No'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _taxClaimableSelection = v;
                                query = v;
                              });
                            }
                          },
                        )
                      : TextField(
                          onChanged: (v) => query = v,
                          decoration: const InputDecoration(
                            labelText: "Search value",
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                          ),
                        ),
                ),

                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: "Add another filter",
                  onPressed: () {
                    if (query.trim().isNotEmpty) {
                      setState(() {
                        filterConditions.add({
                          "key": selectedFilter,
                          "value": query.trim(),
                        });
                        query = "";
                      });
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (filterConditions.isNotEmpty)
              Wrap(
                spacing: 6,
                children: filterConditions
                    .map(
                      (f) => Chip(
                        label: Text("${f['key']}: ${f['value']}"),
                        onDeleted: () => setState(() {
                          filterConditions.remove(f);
                        }),
                      ),
                    )
                    .toList(),
              ),

            const Spacer(),

            ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text("Apply Filters"),
              onPressed: () => buildResults(context),
            ),
          ],
        ),
      );
    },
  );
}
}
