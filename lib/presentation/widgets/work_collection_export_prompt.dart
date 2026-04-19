import 'package:flutter/material.dart';
import 'package:receiptnest/presentation/widgets/smart_prompt_card.dart';

class WorkCollectionExportPrompt extends StatelessWidget {
  const WorkCollectionExportPrompt({
    super.key,
    required this.onPrimaryAction,
    required this.onSecondaryAction,
  });

  final VoidCallback? onPrimaryAction;
  final VoidCallback onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return SmartPromptCard(
      icon: Icons.check_circle_outline,
      title: 'Trip completed',
      description:
          'Download your receipts and summary for easy reimbursement or records.',
      primaryActionText: 'Download report',
      onPrimaryAction: onPrimaryAction,
      secondaryActionText: 'Not now',
      onSecondaryAction: onSecondaryAction,
    );
  }
}
