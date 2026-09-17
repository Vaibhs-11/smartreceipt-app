import 'package:receiptnest/domain/entities/app_user.dart';

abstract class UserRepository {
  Future<AppUserProfile?> getCurrentUserProfile();
  Future<void> startTrial();
  Future<void> markDowngradeRequired();
  Future<void> clearDowngradeRequired();
}
