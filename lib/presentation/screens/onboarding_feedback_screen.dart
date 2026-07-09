import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';
import 'package:receiptnest/services/connectivity_service.dart';

class OnboardingFeedbackScreen extends StatefulWidget {
  const OnboardingFeedbackScreen({super.key});

  @override
  State<OnboardingFeedbackScreen> createState() =>
      _OnboardingFeedbackScreenState();
}

class _OnboardingFeedbackScreenState extends State<OnboardingFeedbackScreen> {
  static const List<String> _reasons = [
    'OCR result was wrong',
    'App was confusing',
    'I do not want to create an account',
    'I was only testing',
    'Something else',
  ];

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String? _reason;
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a reason before sending.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final connectivity = ConnectivityService();
      if (!await ensureInternetConnection(context, connectivity)) return;
      final callable = FirebaseFunctions.instance.httpsCallable(
        'submitOnboardingFeedback',
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'reason': reason,
        'message': _messageController.text.trim(),
        'replyEmail': _emailController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Thanks for the feedback.')));
      await _discardAnonymousSession();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send feedback right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _discardAnonymousSession() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) return;
    await fb_auth.FirebaseAuth.instance.signOut();
  }

  Future<void> _skip() async {
    await _discardAnonymousSession();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share feedback')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.rate_review_outlined,
                    size: 44,
                    color: AppColors.primaryNavy,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'What did not work for you?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your feedback helps improve the first receipt experience.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: _reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: _reasons
                        .map(
                          (reason) => DropdownMenuItem<String>(
                            value: reason,
                            child: Text(reason),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _reason = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    enabled: !_submitting,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Tell us what went wrong (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    enabled: !_submitting,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email if you want a reply (optional)',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send feedback'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _submitting ? null : () => _skip(),
                    child: const Text('Skip and discard receipt'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
