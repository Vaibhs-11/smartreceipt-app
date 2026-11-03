import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receiptnest/core/services/analytics_service.dart';
import 'package:receiptnest/core/services/share_receipt_demo_preferences.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/presentation/screens/share_receipt_demo_screen.dart';

class ShareReceiptDemoPromptCard extends StatefulWidget {
  final String? userId;
  final bool hasSavedReceipt;

  const ShareReceiptDemoPromptCard({
    super.key,
    required this.userId,
    required this.hasSavedReceipt,
  });

  @override
  State<ShareReceiptDemoPromptCard> createState() =>
      _ShareReceiptDemoPromptCardState();
}

class _ShareReceiptDemoPromptCardState
    extends State<ShareReceiptDemoPromptCard> {
  bool _isVisible = false;
  bool _hasLoggedImpression = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    ShareReceiptDemoPreferences.revision.addListener(_loadVisibility);
    _loadVisibility();
  }

  @override
  void dispose() {
    ShareReceiptDemoPreferences.revision.removeListener(_loadVisibility);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ShareReceiptDemoPromptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.hasSavedReceipt != widget.hasSavedReceipt) {
      if (oldWidget.userId != widget.userId) {
        _hasLoggedImpression = false;
      }
      _loadVisibility();
    }
  }

  Future<void> _loadVisibility() async {
    final generation = ++_loadGeneration;
    final userId = widget.userId;
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        userId == null ||
        !widget.hasSavedReceipt) {
      if (mounted && _isVisible) setState(() => _isVisible = false);
      return;
    }

    final shouldShow = await ShareReceiptDemoPreferences.shouldShow(
      userId: userId,
      hasSavedReceipt: widget.hasSavedReceipt,
    );
    if (!mounted || generation != _loadGeneration) return;

    setState(() => _isVisible = shouldShow);
    if (shouldShow && !_hasLoggedImpression) {
      _hasLoggedImpression = true;
      unawaited(AnalyticsService.logShareReceiptDemoShown());
    }
  }

  Future<void> _dismiss() async {
    final userId = widget.userId;
    if (userId == null) return;
    await ShareReceiptDemoPreferences.markDismissed(userId);
    unawaited(AnalyticsService.logShareReceiptDemoDismissed());
    if (mounted) setState(() => _isVisible = false);
  }

  Future<void> _openDemo() async {
    final userId = widget.userId;
    if (userId == null) return;

    unawaited(AnalyticsService.logShareReceiptDemoOpened(source: 'home'));
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const ShareReceiptDemoScreen(),
      ),
    );
    if (completed == true) {
      await ShareReceiptDemoPreferences.markCompleted(userId);
      unawaited(AnalyticsService.logShareReceiptDemoCompleted(source: 'home'));
    } else {
      await ShareReceiptDemoPreferences.markDismissed(userId);
      unawaited(AnalyticsService.logShareReceiptDemoDismissed());
    }
    if (mounted) setState(() => _isVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      color: const Color(0xFFEAF5FA),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.ios_share_outlined,
                    color: AppColors.primaryNavy,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your next receipt is easier to save',
                        style: TextStyle(
                          color: AppColors.primaryNavy,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'In Photos, Files or Mail, tap Share, then ReceiptNest.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _dismiss, child: const Text('Not now')),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                  ),
                  onPressed: _openDemo,
                  child: const Text('See how'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
