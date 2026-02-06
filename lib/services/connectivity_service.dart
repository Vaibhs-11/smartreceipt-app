import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  static const _reachabilityUrl =
      'https://clients3.google.com/generate_204';
  static const Duration _timeout = Duration(seconds: 4);

  Future<bool> hasInternetConnection() async {
    final result = await _connectivity.checkConnectivity();
    if (result == ConnectivityResult.none) {
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse(_reachabilityUrl))
          .timeout(_timeout);
      return response.statusCode == 204 || response.statusCode == 200;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
