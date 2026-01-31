import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Make sure this file (next step) exposes `authControllerProvider`
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/utils/root_scaffold_messenger.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pw2Ctrl = TextEditingController();

  bool _hidePw = true;
  bool _hidePw2 = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    if (!ok) return 'Enter a valid email';
    return null;
  }

  String? _pwValidator(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'At least 6 characters';
    return null;
  }

  String? _pw2Validator(String? v) {
    if (v != _pwCtrl.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _pwCtrl.text;

    // Uses Riverpod controller (wired in Step 2)
    final controller = ref.read(authControllerProvider.notifier);

    try {
      await controller.signUpWithEmailPassword(email, password);
      // AuthGate should navigate automatically when auth state changes.
      showRootSnackBar(
        const SnackBar(content: Text('Account created!')),
      );
      if (mounted) Navigator.of(context).pop(); // go back to Login if you pushed this route
    } catch (e) {
      showRootSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // App title / header
                      Text(
                        'SmartReceipt',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 24),

                      // Email
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: _emailValidator,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: _pwCtrl,
                        obscureText: _hidePw,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _hidePw = !_hidePw),
                            icon: Icon(_hidePw ? Icons.visibility : Icons.visibility_off),
                          ),
                        ),
                        validator: _pwValidator,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password
                      TextFormField(
                        controller: _pw2Ctrl,
                        obscureText: _hidePw2,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _hidePw2 = !_hidePw2),
                            icon: Icon(_hidePw2 ? Icons.visibility : Icons.visibility_off),
                          ),
                        ),
                        validator: _pw2Validator,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Error surface (if any)
                      if (state.hasError)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            state.error.toString(),
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),

                      // Submit
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isLoading ? null : _submit,
                          child: isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Create account'),
                        ),
                      ),

                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isLoading ? null : () => Navigator.pop(context),
                        child: const Text('I already have an account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
