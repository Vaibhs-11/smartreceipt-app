import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:receiptnest/domain/entities/app_config.dart';
import 'package:receiptnest/domain/exceptions/app_config_exception.dart';

class AppConfigRepository {
  AppConfigRepository({FirebaseFirestore? firestoreInstance})
      : _firestore = firestoreInstance ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _configDoc() {
    return _firestore.collection('config').doc('app');
  }

  Future<AppConfig> fetch() async {
    try {
      final snapshot = await _configDoc().get();
      if (!snapshot.exists) {
        throw const AppConfigUnavailableException(
          'App config document missing.',
        );
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      if (data.isEmpty) {
        throw const AppConfigUnavailableException('App config is empty.');
      }
      final config = AppConfig.fromFirestore(data);
      debugPrint(
        'Loaded app config: freeLimit=${config.freeReceiptLimit}, '
        'premiumLimit=${config.premiumReceiptLimit}, '
        'enablePaidTiers=${config.enablePaidTiers}',
      );
      return config;
    } catch (e) {
      debugPrint('Failed to load app config: $e');
      rethrow;
    }
  }
}
