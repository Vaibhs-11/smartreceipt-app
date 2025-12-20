import 'package:smartreceipt/domain/entities/app_user.dart';

abstract class UserRepository {
  Future<AppUserProfile> getCurrentUserProfile();
  Future<void> startTrial();
  Future<void> setPaid(DateTime subscriptionEndsAt);
  Future<void> markDowngradeRequired();
  Future<void> clearDowngradeRequired();
}
