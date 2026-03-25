import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/domain/entities/app_config.dart';
import 'package:receiptnest/presentation/providers/app_config_provider.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/routes/app_routes.dart';
import 'package:receiptnest/presentation/screens/keep3_selection_screen.dart';
import 'package:receiptnest/presentation/screens/purchase_screen.dart';
import 'package:receiptnest/presentation/screens/home_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';

class TrialEndedGateScreen extends ConsumerWidget {
  const TrialEndedGateScreen({
    super.key,
    required this.isSubscriptionEnded,
    required this.receiptCount,
  });

  final bool isSubscriptionEnded;
  final int receiptCount;

  String get _title =>
      isSubscriptionEnded ? 'Your subscription has expired' : 'Your free trial has ended';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(appConfigProvider);
    return configAsync.when(
      loading: () => _loadingScaffold(),
      error: (e, _) => _configErrorScaffold(ref),
      data: (appConfig) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(_title),
            ),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Your free trial has ended',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Upgrade to Premium to:',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const _ValueItem('Keep all your receipts'),
                            const SizedBox(height: 12),
                            const _ValueItem('Unlock categories and smart search'),
                            const SizedBox(height: 12),
                            const _ValueItem('Stay organised without limits'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PurchaseScreen(),
                                settings: const RouteSettings(name: AppRoutes.purchase),
                              ),
                            );
                          },
                          icon: const Icon(Icons.workspace_premium_outlined),
                          label: const Text('Upgrade to Premium'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          final connectivity = ref.read(connectivityServiceProvider);
                          if (!await ensureInternetConnection(context, connectivity)) {
                            return;
                          }
                          final userRepo = ref.read(userRepositoryProvider);
                          if (receiptCount > appConfig.freeReceiptLimit) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => Keep3SelectionScreen(
                                  isSubscriptionEnded: isSubscriptionEnded,
                                ),
                                settings: const RouteSettings(
                                  name: AppRoutes.keep3Selection,
                                ),
                              ),
                            );
                            return;
                          }

                          await userRepo.clearDowngradeRequired();
                          if (context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const HomeScreen(),
                                settings: const RouteSettings(name: AppRoutes.home),
                              ),
                              (_) => false,
                            );
                          }
                        },
                        child: const Text('Continue with free (limit applies)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loadingScaffold() {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_title),
      ),
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _configErrorScaffold(WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_title),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unable to load app settings.'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                ref.refresh(appConfigProvider);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueItem extends StatelessWidget {
  const _ValueItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
