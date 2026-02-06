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

  String _body(AppConfig appConfig) {
    final freeLimit = appConfig.freeReceiptLimit;
    if (receiptCount > freeLimit) {
      if (isSubscriptionEnded) {
        return 'Your subscription has expired. Please delete receipts to continue or upgrade. '
            'You can keep up to $freeLimit receipts on the free plan.';
      }
      return 'To continue on the free plan, please choose exactly $freeLimit receipts to keep. '
          'Upgrade to keep everything and unlock Premium.';
    }
    return 'Choose Premium to keep all receipts, or continue on the free plan with up to $freeLimit receipts.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(appConfigProvider);
    final appConfig =
        configAsync.maybeWhen(data: (c) => c, orElse: () => const AppConfig());
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_title),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                _title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                _body(appConfig),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const PurchaseScreen(),
                      settings: const RouteSettings(name: AppRoutes.purchase),
                    ),
                  );
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Upgrade to Premium'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
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
                        settings:
                            const RouteSettings(name: AppRoutes.keep3Selection),
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
                child: const Text('Continue on Free Plan'),
              ),
              const SizedBox(height: 12),
              const Text(
                'This gate is required to keep your data consistent. You can still view, search, '
                'and export while gated.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
