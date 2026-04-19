import 'package:flutter/material.dart';

class SmartPromptCard extends StatelessWidget {
  const SmartPromptCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryActionText,
    required this.onPrimaryAction,
    required this.secondaryActionText,
    required this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryActionText;
  final VoidCallback? onPrimaryAction;
  final String secondaryActionText;
  final VoidCallback onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryTint = colorScheme.primary.withValues(alpha: 0.05);
    final borderColor = colorScheme.primary.withValues(alpha: 0.15);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 28,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Takes ~5 seconds',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: onPrimaryAction,
                child: Text(primaryActionText),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
