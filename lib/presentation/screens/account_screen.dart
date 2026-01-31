import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';
import 'package:smartreceipt/domain/entities/app_config.dart';
import 'package:smartreceipt/domain/entities/app_user.dart';
import 'package:smartreceipt/domain/entities/subscription_entitlement.dart';
import 'package:smartreceipt/domain/exceptions/account_deletion_exception.dart';
import 'package:smartreceipt/presentation/providers/app_config_provider.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/providers/receipt_search_filters_provider.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/purchase_screen.dart';
import 'package:smartreceipt/presentation/utils/root_scaffold_messenger.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _changingPassword = false;
  bool _startingTrial = false;
  bool _restoringPurchases = false;
  bool _deletingAccount = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppUser?>>(authStateProvider, (_, next) {
      final user = next.maybeWhen(data: (value) => value, orElse: () => null);
      if (user == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        });
      }
    });

    final userAsync = ref.watch(userProfileProvider);
    final countAsync = ref.watch(receiptCountProvider);
    final configAsync = ref.watch(appConfigProvider);
    final appConfig =
        configAsync.maybeWhen(data: (c) => c, orElse: () => const AppConfig());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
      ),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load account: $e')),
          data: (profile) {
            if (profile == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              });
              return const SizedBox.shrink();
            }
            final receiptCount = countAsync.maybeWhen(
              data: (v) => v,
              orElse: () => 0,
            );
            return RefreshIndicator(
              onRefresh: () async {
                ref.refresh(userProfileProvider);
                ref.refresh(receiptCountProvider);
                ref.refresh(appConfigProvider);
                await Future.wait([
                  ref.read(userProfileProvider.future),
                  ref.read(receiptCountProvider.future),
                  ref.read(appConfigProvider.future),
                ]);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Profile'),
                    _userInfo(profile),
                    const SizedBox(height: 16),
                    _statusCard(profile, receiptCount, appConfig),
                    const SizedBox(height: 24),
                    if (!profile.isAnonymous) ...[
                      _sectionTitle('Security'),
                      _securityCard(profile),
                      const SizedBox(height: 24),
                    ],
                    _sectionTitle('General'),
                    _generalCard(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _userInfo(AppUserProfile profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.isAnonymous
                  ? 'Anonymous user'
                  : (profile.email ?? 'No email'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            if (profile.createdAt != null)
              Text(
                'Joined ${DateFormat.yMMMd().format(profile.createdAt!.toLocal())}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[700]),
              ),
            if (profile.isAnonymous) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create an account to keep your receipts safe',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed(AppRoutes.signup);
                      },
                      child: const Text('Sign up'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusCard(
      AppUserProfile profile, int receiptCount, AppConfig appConfig) {
    final now = DateTime.now().toUtc();
    final freeLimit = appConfig.freeReceiptLimit;
    final remaining = freeLimit - receiptCount;
    final remainingClamped = remaining < 0 ? 0 : remaining;
    final trialEnds = profile.trialEndsAt;
    final subscriptionActive = profile.subscriptionStatus ==
            SubscriptionStatus.active &&
        profile.subscriptionTier.isPaid;
    final subscriptionExpired =
        profile.subscriptionStatus == SubscriptionStatus.expired;

    String title;
    String body;
    String? caption;
    Widget primaryCta = const SizedBox.shrink();
    Widget? secondaryCta;
    Color badgeColor;
    IconData badgeIcon;
    String badgeLabel;
    if (subscriptionActive) {
      badgeLabel = profile.subscriptionTier == SubscriptionTier.yearly
          ? 'Yearly'
          : 'Monthly';
      badgeIcon = Icons.workspace_premium_outlined;
      badgeColor = Colors.green;
      title = 'You’re on the ${badgeLabel} plan';
      body = 'Unlimited receipts while your subscription is active.';
      caption = Theme.of(context).platform == TargetPlatform.iOS
          ? 'Billing managed by Apple App Store'
          : 'Billing managed by Google Play';
      primaryCta = TextButton(
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Manage subscription'),
              content: Text(
                Theme.of(context).platform == TargetPlatform.iOS
                    ? 'Manage your subscription in the App Store.'
                    : 'Manage your subscription in Google Play.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
        child: const Text('Manage subscription'),
      );
    } else if (profile.accountStatus == AccountStatus.trial) {
      final daysLeft = trialEnds != null
          ? trialEnds.difference(now).inDays.clamp(0, 999)
          : null;
      badgeLabel = 'Free trial';
      badgeIcon = Icons.hourglass_empty_outlined;
      badgeColor = Colors.orange;
      title = 'Your trial ends in ${daysLeft ?? 'a few'} days';
      body = 'Keep all your receipts when you upgrade to Premium.';
      primaryCta = FilledButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PurchaseScreen()),
          );
        },
        child: const Text('Upgrade to Premium'),
      );
    } else {
      badgeLabel = 'Free';
      badgeIcon = Icons.lock_open_outlined;
      badgeColor = Colors.blue;
      title = subscriptionExpired
          ? 'Your subscription has expired'
          : 'You’re on the Free plan';
      body = subscriptionExpired
          ? 'Delete receipts to stay within $freeLimit, or upgrade to keep adding more.'
          : 'You have $remainingClamped of $freeLimit receipts remaining.';
      if (subscriptionExpired) {
        primaryCta = FilledButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PurchaseScreen()),
            );
          },
          child: const Text('Upgrade'),
        );
      } else {
        primaryCta = FilledButton(
          onPressed: _startingTrial ? null : () => _startTrial(),
          child: _startingTrial
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Start free trial'),
        );
        secondaryCta = TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PurchaseScreen()),
            );
          },
          child: const Text('Upgrade'),
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(badgeIcon, color: badgeColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 16),
            primaryCta,
            if (secondaryCta != null) ...[
              const SizedBox(height: 6),
              secondaryCta!,
            ],
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _restoringPurchases ? null : _restorePurchases,
              icon: _restoringPurchases
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore),
              label: const Text('Restore purchases'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _securityCard(AppUserProfile profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              subtitle: const Text('Update your sign-in password'),
              onTap: _changingPassword ? null : () => _changePassword(profile),
              trailing: _changingPassword
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mark_email_read_outlined),
              title: const Text('Send password reset link'),
              subtitle: const Text('We will email a reset link'),
              onTap: () async {
                final email = profile.email;
                if (email == null || email.isEmpty) return;
                try {
                  await fb_auth.FirebaseAuth.instance
                      .sendPasswordResetEmail(email: email);
                  if (!mounted) return;
                  showRootSnackBar(
                    const SnackBar(
                      content: Text(
                          'If an account exists for this email, a password reset link has been sent.'),
                    ),
                  );
                } catch (_) {
                  if (!mounted) return;
                  showRootSnackBar(
                    const SnackBar(
                      content: Text(
                          'If an account exists for this email, a password reset link has been sent.'),
                    ),
                  );
                }
              },
              trailing: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _generalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
              onPressed: () async {
                await ref.read(authServiceProvider).signOut();
                ref.read(receiptSearchFiltersProvider.notifier).state =
                    const ReceiptSearchFilters();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
            const Divider(),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
              onPressed: _deletingAccount ? null : _confirmDeleteAccount,
              icon: _deletingAccount
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever_outlined),
              label: const Text('Delete Account'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startTrial() async {
    final userRepo = ref.read(userRepositoryProvider);
    setState(() => _startingTrial = true);
    try {
      await userRepo.startTrial();
      ref.refresh(userProfileProvider);
      if (!mounted) return;
      showRootSnackBar(
        const SnackBar(content: Text('Trial started')),
      );
    } catch (e) {
      if (!mounted) return;
      showRootSnackBar(
        SnackBar(content: Text('Could not start trial: $e')),
      );
    } finally {
      if (mounted) setState(() => _startingTrial = false);
    }
  }

  Future<void> _restorePurchases() async {
    if (_restoringPurchases) return;
    setState(() => _restoringPurchases = true);
    final subscriptionService = ref.read(subscriptionServiceProvider);
    final userRepo = ref.read(userRepositoryProvider);
    try {
      await subscriptionService.restorePurchases();
      final profile = await userRepo.getCurrentUserProfile();
      if (profile != null) {
        final entitlement = await subscriptionService.getCurrentEntitlement();
        await userRepo.applySubscriptionEntitlement(
          entitlement,
          currentProfile: profile,
        );
      }
      ref.refresh(userProfileProvider);
      if (!mounted) return;
      showRootSnackBar(
        const SnackBar(content: Text('Purchases restored.')),
      );
    } catch (e) {
      if (!mounted) return;
      showRootSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _restoringPurchases = false);
    }
  }

  Future<void> _changePassword(AppUserProfile profile) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Change password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Current password'),
                ),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Update'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final current = currentCtrl.text.trim();
    final updated = newCtrl.text.trim();
    if (current.isEmpty || updated.isEmpty) return;

    setState(() => _changingPassword = true);

    try {
      final user = fb_auth.FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('Not signed in with email/password');
      }

      final credential = fb_auth.EmailAuthProvider.credential(
        email: user.email!,
        password: current,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(updated);

      if (!mounted) return;
      showRootSnackBar(
        const SnackBar(content: Text('Password updated')),
      );
    } catch (e) {
      if (!mounted) return;
      showRootSnackBar(
        SnackBar(content: Text('Failed to update password: $e')),
      );
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Account'),
            content: const Text(
              'This will permanently delete your account and all your receipts. '
              'This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    setState(() => _deletingAccount = true);
    try {
      final deleteAccount = ref.read(deleteAccountUseCaseProvider);
      await deleteAccount();
      ref.refresh(userProfileProvider);
      ref.refresh(receiptCountProvider);
      ref.refresh(receiptsProvider);
    } on AccountDeletionFunctionException catch (e) {
      debugPrint(
        'Account deletion failed via Cloud Function '
        '(code: ${e.code}, message: ${e.message})',
      );
    } catch (e) {
      debugPrint('Account deletion failed: $e');
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }
}
