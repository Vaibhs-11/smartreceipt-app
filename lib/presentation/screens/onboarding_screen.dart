import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/core/constants/app_constants.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/add_receipt_screen.dart';
import 'package:receiptnest/presentation/screens/login_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startReceiptPreview() async {
    final connectivity = ref.read(connectivityServiceProvider);
    if (!await ensureInternetConnection(context, connectivity)) return;
    if (!mounted) return;

    try {
      await ref.read(authControllerProvider.notifier).signInAnonymously();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to start receipt preview. Please try again.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AddReceiptScreen(isOnboardingPreview: true),
      ),
    );
  }

  void _openLogin() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/branding/receipt_nest_logo.png',
                      height: 72,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Store, organise, and search your receipts without the shoebox.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _ReceiptPreviewAnimation(controller: _animationController),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _startReceiptPreview,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan or upload a receipt'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openLogin,
                    icon: const Icon(Icons.login),
                    label: const Text('Log in'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryNavy,
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: AppColors.primaryNavy),
                    ),
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

class _ReceiptPreviewAnimation extends StatelessWidget {
  const _ReceiptPreviewAnimation({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final scan = 42 + (controller.value * 134);
        return Container(
          height: 260,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                const _ExtractionHighlights(),
                Positioned(
                  left: 22,
                  right: 22,
                  top: scan,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.accentTeal,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x661FA7A5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExtractionHighlights extends StatelessWidget {
  const _ExtractionHighlights();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(child: _ReceiptInputCard()),
          SizedBox(width: 14),
          Expanded(
            child: _ExtractedSummary(),
          ),
        ],
      ),
    );
  }
}

class _ExtractedSummary extends StatelessWidget {
  const _ExtractedSummary();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          alignment: Alignment.topCenter,
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: constraints.maxWidth,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ExtractedField(
                  icon: Icons.storefront_outlined,
                  label: 'Store',
                  value: 'Market Lane Grocer',
                ),
                SizedBox(height: 8),
                _ExtractedField(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: 'Apr 18, 2026',
                ),
                SizedBox(height: 8),
                _ExtractedField(
                  icon: Icons.payments_outlined,
                  label: 'Total',
                  value: 'AUD 48.65',
                ),
                SizedBox(height: 10),
                _ExtractedItemsCard(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReceiptInputCard extends StatelessWidget {
  const _ReceiptInputCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 18,
                color: AppColors.primaryNavy,
              ),
              SizedBox(width: 8),
              Text(
                'Receipt',
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _ReceiptLine(widthFactor: 0.78, height: 12),
          const SizedBox(height: 12),
          const _ReceiptLine(widthFactor: 0.96),
          const SizedBox(height: 8),
          const _ReceiptLine(widthFactor: 0.82),
          const SizedBox(height: 8),
          const _ReceiptLine(widthFactor: 0.9),
          const Spacer(),
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.accentTeal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'OCR scan',
                style: TextStyle(
                  color: AppColors.accentTeal,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({required this.widthFactor, this.height = 8});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _ExtractedField extends StatelessWidget {
  const _ExtractedField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.accentTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtractedItemsCard extends StatelessWidget {
  const _ExtractedItemsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items found',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          _ExtractedItemRow(name: 'Flat white', price: '5.20'),
          SizedBox(height: 4),
          _ExtractedItemRow(name: 'Reusable tote', price: '3.50'),
          SizedBox(height: 4),
          _ExtractedItemRow(name: 'Sourdough loaf', price: '8.95'),
        ],
      ),
    );
  }
}

class _ExtractedItemRow extends StatelessWidget {
  const _ExtractedItemRow({required this.name, required this.price});

  final String name;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          price,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
