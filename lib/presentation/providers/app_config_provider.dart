import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/data/repositories/app_config_repository.dart';
import 'package:smartreceipt/domain/entities/app_config.dart';

final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  return AppConfigRepository();
});

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  final repository = ref.watch(appConfigRepositoryProvider);
  return repository.fetch();
});
