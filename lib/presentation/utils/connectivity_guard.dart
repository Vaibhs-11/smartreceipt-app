import 'package:flutter/material.dart';
import 'package:receiptnest/services/connectivity_service.dart';

Future<bool> ensureInternetConnection(
  BuildContext context,
  ConnectivityService service,
) async {
  final hasConnection = await service.hasInternetConnection();
  if (hasConnection) return true;
  if (!context.mounted) return false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('No internet connection'),
      content: const Text(
        'SmartReceipt needs an internet connection to scan and extract receipt details. Please connect to the internet and try again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  return false;
}
