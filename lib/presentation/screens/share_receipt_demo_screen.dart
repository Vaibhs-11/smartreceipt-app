import 'package:flutter/material.dart';
import 'package:receiptnest/core/theme/app_colors.dart';

class ShareReceiptDemoScreen extends StatefulWidget {
  const ShareReceiptDemoScreen({super.key});

  @override
  State<ShareReceiptDemoScreen> createState() => _ShareReceiptDemoScreenState();
}

class _ShareReceiptDemoScreenState extends State<ShareReceiptDemoScreen> {
  static const List<_DemoPage> _pages = [
    _DemoPage(
      assetPath: 'assets/share_receipt_demo/01_open_receipt.png',
      semanticsLabel: 'Open a receipt in Photos, Files, or Mail and tap Share.',
    ),
    _DemoPage(
      assetPath: 'assets/share_receipt_demo/02_choose_receiptnest.png',
      semanticsLabel:
          'Choose ReceiptNest in the Share Sheet. Tap More if needed.',
    ),
    _DemoPage(
      assetPath: 'assets/share_receipt_demo/03_review_save.png',
      semanticsLabel: 'Review the scanned receipt details and tap Save.',
    ),
  ];

  final PageController _pageController = PageController();
  int _pageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_pageIndex == _pages.length - 1) {
      Navigator.of(context).pop(true);
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Save receipts from anywhere'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() => _pageIndex = index);
                  },
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Semantics(
                        label: page.semanticsLabel,
                        image: true,
                        child: Image.asset(
                          page.assetPath,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Text(
                      '${_pageIndex + 1} of ${_pages.length}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    if (_pageIndex > 0)
                      TextButton(
                        onPressed: () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                        ),
                        child: const Text('Back'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryNavy,
                      ),
                      onPressed: _next,
                      child: Text(
                        _pageIndex == _pages.length - 1 ? 'Done' : 'Next',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoPage {
  final String assetPath;
  final String semanticsLabel;

  const _DemoPage({required this.assetPath, required this.semanticsLabel});
}
