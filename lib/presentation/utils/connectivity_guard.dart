import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:receiptnest/services/connectivity_service.dart';

Future<bool> ensureInternetConnection(
  BuildContext context,
  ConnectivityService service,
) async {
  final hasConnection = await service.hasInternetConnection();
  if (hasConnection) return true;
  if (!context.mounted) return false;

  await showNoInternetDialog(context);

  return false;
}

Future<void> showNoInternetDialog(BuildContext context) async {
  if (!context.mounted) return;
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
}

bool isNetworkException(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return true;
  }

  if (error is fb_auth.FirebaseAuthException) {
    return _isNetworkCode(error.code);
  }

  if (error is FirebaseFunctionsException) {
    return _isNetworkCode(error.code);
  }

  if (error is FirebaseException) {
    return _isNetworkCode(error.code);
  }

  return false;
}

bool _isNetworkCode(String? code) {
  if (code == null) return false;
  return code == 'network-request-failed' ||
      code == 'unavailable' ||
      code == 'timeout';
}
