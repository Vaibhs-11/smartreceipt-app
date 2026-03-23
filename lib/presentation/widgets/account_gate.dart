import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/domain/policies/account_policies.dart';
import 'package:receiptnest/domain/exceptions/app_config_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/presentation/providers/app_config_provider.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/routes/app_routes.dart';
import 'package:receiptnest/presentation/screens/trial_ended_gate_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';

/// Observes lifecycle and enforces account gates on app start/resume.
class AccountGate extends ConsumerStatefulWidget {
  const AccountGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends ConsumerState<AccountGate>
    with WidgetsBindingObserver {
  bool _checking = false;
  bool? _wasPremiumEligible;
  bool _trialEndGateShown = false;
  static const String _trialEndedGateStorageKeyPrefix = 'trialEndedGateSeen';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkGate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkGate();
    }
  }

  Future<void> _checkGate() async {
    if (_checking) return;
    _checking = true;
    try {
      final uid = ref.read(currentUidProvider);
      if (uid == null) {
        _wasPremiumEligible = null;
        _trialEndGateShown = false;
        return;
      }
      final connectivity = ref.read(connectivityServiceProvider);
      if (!await ensureInternetConnection(context, connectivity)) {
        return;
      }
      final userRepo = ref.read(userRepositoryProvider);
      final receiptRepo = ref.read(receiptRepositoryProviderOverride);
      final subscriptionService = ref.read(subscriptionServiceProvider);
      final now = DateTime.now().toUtc();
      final appConfig = await ref.read(appConfigProvider.future);

      final profile = await userRepo.getCurrentUserProfile();
      if (profile == null) {
        return;
      }
      try {
        final entitlement = await subscriptionService.getCurrentEntitlement();
        await userRepo.applySubscriptionEntitlement(
          entitlement,
          currentProfile: profile,
        );
      } catch (e) {
        debugPrint('Subscription sync failed: $e');
      }

      final refreshedProfile = await userRepo.getCurrentUserProfile();
      if (refreshedProfile == null) {
        return;
      }
      final receiptCount = await receiptRepo.getReceiptCount();

      final eligibility = AccountPolicies.evaluate(refreshedProfile, now);
      final trialExpired = eligibility.trialExpired;
      final subscriptionExpired = AccountPolicies.isSubscriptionExpired(
        refreshedProfile,
      );
      final isExpired = trialExpired || subscriptionExpired;
      final expiryEventMarker = _buildExpiryEventMarker(
        profile: refreshedProfile,
        trialExpired: trialExpired,
        subscriptionExpired: subscriptionExpired,
      );
      final alreadyShownForCurrentEvent =
          await _hasSeenGateForExpiryEvent(uid, expiryEventMarker);
      final becameExpired = _wasPremiumEligible == true && !eligibility.isPremiumEligible;
      final firstExpiredRead =
          _wasPremiumEligible == null && isExpired && !eligibility.isPremiumEligible;

      if ((trialExpired || subscriptionExpired) &&
          receiptCount <= appConfig.freeReceiptLimit) {
        await userRepo.clearDowngradeRequired();
      } else if ((trialExpired || subscriptionExpired) &&
          receiptCount > appConfig.freeReceiptLimit) {
        await userRepo.markDowngradeRequired();
      }

      final needsGate = AccountPolicies.downgradeRequired(
        refreshedProfile,
        receiptCount,
        now,
        appConfig,
      );

      final shouldShowGate = needsGate || becameExpired || firstExpiredRead;

      if (!isExpired) {
        await _clearSeenGateForUid(uid);
        _trialEndGateShown = false;
      }

      if (shouldShowGate &&
          !_trialEndGateShown &&
          !alreadyShownForCurrentEvent &&
          mounted) {
        await _markGateShownForExpiryEvent(uid, expiryEventMarker);
        _trialEndGateShown = true;
        _wasPremiumEligible = eligibility.isPremiumEligible;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => TrialEndedGateScreen(
              isSubscriptionEnded: subscriptionExpired,
              receiptCount: receiptCount,
            ),
            settings: const RouteSettings(name: AppRoutes.trialEndedGate),
          ),
          (_) => false,
        );
        return;
      }

      _wasPremiumEligible = eligibility.isPremiumEligible;
    } catch (e) {
      if (e is AppConfigUnavailableException && mounted) {
        final retry = await _showConfigUnavailableDialog();
        if (retry) {
          ref.refresh(appConfigProvider);
          _checkGate();
        }
        return;
      }
      if (isNetworkException(e)) {
        if (mounted) {
          await showNoInternetDialog(context);
        }
        return;
      }
      debugPrint('Account gate check failed: $e');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SizedBox.shrink();
    return widget.child;
  }

  Future<bool> _showConfigUnavailableDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('App settings unavailable'),
        content: const Text('Unable to load account limits. Please try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String? _buildExpiryEventMarker({
    required AppUserProfile profile,
    required bool trialExpired,
    required bool subscriptionExpired,
  }) {
    if (!trialExpired && !subscriptionExpired) return null;

    if (trialExpired && profile.trialEndsAt != null) {
      return 'trial:${profile.trialEndsAt!.toUtc().millisecondsSinceEpoch}';
    }

    if (subscriptionExpired && profile.subscriptionEndsAt != null) {
      return 'subscription:${profile.subscriptionEndsAt!.toUtc().millisecondsSinceEpoch}';
    }

    if (trialExpired) return 'trial:expired:unknown';
    return 'subscription:expired:unknown';
  }

  String _seenGateStorageKey(String uid) {
    return '$_trialEndedGateStorageKeyPrefix:$uid';
  }

  Future<bool> _hasSeenGateForExpiryEvent(
    String uid,
    String? expiryEventMarker,
  ) async {
    if (expiryEventMarker == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = _seenGateStorageKey(uid);
    final seenMarker = prefs.getString(key);
    return seenMarker == expiryEventMarker;
  }

  Future<void> _markGateShownForExpiryEvent(
    String uid,
    String? expiryEventMarker,
  ) async {
    if (expiryEventMarker == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _seenGateStorageKey(uid);
    await prefs.setString(key, expiryEventMarker);
  }

  Future<void> _clearSeenGateForUid(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_seenGateStorageKey(uid));
  }
}
