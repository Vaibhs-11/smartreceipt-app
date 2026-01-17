import 'package:smartreceipt/domain/entities/app_user.dart';
import 'package:smartreceipt/domain/entities/subscription_entitlement.dart';

abstract class UserRepository {
  Future<AppUserProfile?> getCurrentUserProfile();
  Future<void> startTrial();
  Future<void> applySubscriptionEntitlement(
    SubscriptionEntitlement entitlement, {
    AppUserProfile? currentProfile,
  });
  Future<void> markDowngradeRequired();
  Future<void> clearDowngradeRequired();
}
