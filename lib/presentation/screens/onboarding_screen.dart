import 'package:flutter/material.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 32),
            const Text(
              'SmartReceipt',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Scan, store, and find your receipts with ease. Works offline. Upgrade for cloud sync.',
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.home),
              child: const Text('Get started'),
            ),
          ],
        ),
      ),
    );
  }
}


