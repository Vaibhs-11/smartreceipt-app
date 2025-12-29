import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/home_screen.dart';

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  bool _processing = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Upgrade to Premium'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Premium keeps unlimited receipts and all features. '
                'Purchasing via App Store / Play Store will be wired later.',
              ),
              const SizedBox(height: 24),
              _planTile(
                title: 'Monthly',
                price: '\$3 / month',
                onPressed: () => _simulate(Duration(days: 30)),
              ),
              _planTile(
                title: 'Yearly',
                price: '\$25 / year',
                onPressed: () => _simulate(Duration(days: 365)),
              ),
              const SizedBox(height: 12),
              if (_message != null)
                Text(
                  _message!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planTile({
    required String title,
    required String price,
    required VoidCallback onPressed,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(price),
        trailing: ElevatedButton(
          onPressed: _processing
              ? null
              : () {
                  if (!kDebugMode) {
                    setState(() {
                      _message =
                          'In-app purchases will be added in production builds.';
                    });
                    return;
                  }
                  onPressed();
                },
          child: Text(kDebugMode ? 'Simulate purchase' : 'Coming soon'),
        ),
      ),
    );
  }

  Future<void> _simulate(Duration duration) async {
    final repo = ref.read(userRepositoryProvider);
    setState(() {
      _processing = true;
      _message = null;
    });
    final now = DateTime.now().toUtc();
    await repo.setPaid(now.add(duration));

    if (!mounted) return;
    setState(() {
      _message = 'Premium activated (simulated).';
      _processing = false;
    });

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const HomeScreen(),
        settings: const RouteSettings(name: AppRoutes.home),
      ),
      (_) => false,
    );
  }
}
