import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartreceipt/domain/entities/app_user.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/routes/app_routes.dart';
import 'package:smartreceipt/presentation/screens/purchase_screen.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _changingPassword = false;
  bool _startingTrial = false;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);
    final countAsync = ref.watch(receiptCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
      ),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load account: $e')),
          data: (profile) {
            final receiptCount = countAsync.maybeWhen(
              data: (v) => v,
              orElse: () => 0,
            );
            return RefreshIndicator(
              onRefresh: () async {
                ref.refresh(userProfileProvider);
                ref.refresh(receiptCountProvider);
                await Future.wait([
                  ref.read(userProfileProvider.future),
                  ref.read(receiptCountProvider.future),
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
                    _statusCard(profile, receiptCount),
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

  Widget _statusCard(AppUserProfile profile, int receiptCount) {
    final now = DateTime.now().toUtc();
    final status = profile.accountStatus;
    final remaining = (3 - receiptCount).clamp(0, 3);
    final trialEnds = profile.trialEndsAt;
    final subsEnds = profile.subscriptionEndsAt;

    String title;
    String body;
    String? caption;
    Widget primaryCta = const SizedBox.shrink();
    Widget? secondaryCta;
    Color badgeColor;
    IconData badgeIcon;
    String badgeLabel;
    switch (status) {
      case AccountStatus.free:
        badgeLabel = 'Free';
        badgeIcon = Icons.lock_open_outlined;
        badgeColor = Colors.blue;
        title = 'You’re on the Free plan';
        body = 'You have $remaining of 3 receipts remaining.';
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
        break;
      case AccountStatus.trial:
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
        break;
      case AccountStatus.paid:
        final source = Theme.of(context).platform == TargetPlatform.iOS
            ? 'Billing managed by Apple App Store'
            : 'Billing managed by Google Play';
        final renewal = subsEnds != null
            ? 'Renews/ends on ${DateFormat.yMMMd().format(subsEnds.toLocal())}'
            : 'Active subscription';
        badgeLabel = 'Premium';
        badgeIcon = Icons.workspace_premium_outlined;
        badgeColor = Colors.green;
        title = 'You’re on the Premium plan';
        body = renewal;
        caption = source;
        primaryCta = TextButton(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Manage subscription'),
                content: Text(
                  'Manage your subscription in the App Store / Play Store.',
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
        break;
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'If an account exists for this email, a password reset link has been sent.'),
                    ),
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
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
              onPressed: () => ref.read(authServiceProvider).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trial started')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start trial: $e')),
      );
    } finally {
      if (mounted) setState(() => _startingTrial = false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update password: $e')),
      );
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }
}
