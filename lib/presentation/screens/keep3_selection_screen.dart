import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';

class Keep3SelectionScreen extends ConsumerStatefulWidget {
  const Keep3SelectionScreen({super.key, required this.isSubscriptionEnded});

  final bool isSubscriptionEnded;

  @override
  ConsumerState<Keep3SelectionScreen> createState() =>
      _Keep3SelectionScreenState();
}

class _Keep3SelectionScreenState extends ConsumerState<Keep3SelectionScreen> {
  final Set<String> _selected = <String>{};
  bool _processing = false;
  String? _error;
  bool _autoCleared = false;

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(receiptsProvider);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            widget.isSubscriptionEnded
                ? 'Subscription ended'
                : 'Trial ended',
          ),
        ),
        body: receiptsAsync.when(
          data: (receipts) {
            if (receipts.length <= 3) {
              // Nothing to choose, just clear gate and continue.
              if (!_autoCleared) {
                _autoCleared = true;
                _autoClear();
              }
              return const Center(child: CircularProgressIndicator());
            }

            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        'Select exactly three receipts to keep on the free plan. '
                        'All others will be permanently deleted after confirmation.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: receipts.length,
                        itemBuilder: (_, index) {
                          final receipt = receipts[index];
                          final selected = _selected.contains(receipt.id);
                          final subtitle =
                              '${DateFormat.yMMMd().format(receipt.date)} · ${receipt.currency} ${receipt.total.toStringAsFixed(2)}';
                          return CheckboxListTile(
                            value: selected,
                            onChanged: _processing
                                ? null
                                : (val) {
                                    setState(() {
                                      if (val == true) {
                                        if (_selected.length < 3) {
                                          _selected.add(receipt.id);
                                        }
                                      } else {
                                        _selected.remove(receipt.id);
                                      }
                                    });
                                  },
                            title: Text(receipt.storeName),
                            subtitle: Text(subtitle),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: !_processing && _selected.length == 3
                                ? _confirmAndFinalize
                                : null,
                            child: Text(
                              _selected.length == 3
                                  ? 'Keep these 3 receipts'
                                  : 'Select 3 to keep',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This is irreversible. Exports are recommended before deleting.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_processing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Finalizing downgrade…',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading receipts: $e')),
        ),
      ),
    );
  }

  Future<void> _autoClear() async {
    final userRepo = ref.read(userRepositoryProvider);
    await userRepo.clearDowngradeRequired();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: const RouteSettings(name: AppRoutes.home),
        ),
        (_) => false,
      );
    }
  }

  Future<void> _confirmAndFinalize() async {
    final first = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Confirm selection'),
            content: const Text(
              'These receipts will be kept. All others will be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;

    if (!first) return;

    final second = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('This cannot be undone'),
            content: const Text(
              'Do you want to permanently delete all other receipts?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes, delete others'),
              ),
            ],
          ),
        ) ??
        false;

    if (!second) return;
    await _finalizeDowngrade();
  }

  Future<void> _finalizeDowngrade() async {
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('finalizeDowngradeToFree');
      await callable.call(<String, dynamic>{
        'keepReceiptIds': _selected.toList(),
      });

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: const RouteSettings(name: AppRoutes.home),
        ),
        (_) => false,
      );
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _error = e.message ?? 'Failed to finalize downgrade.';
      });
    } catch (e) {
      setState(() {
        _error = 'Unexpected error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }
}
