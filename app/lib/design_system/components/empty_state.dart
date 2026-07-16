import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class BayazEmptyState extends StatelessWidget {
  const BayazEmptyState({
    super.key,
    required this.asset,
    required this.title,
    required this.message,
    this.action,
  });

  final String asset;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(asset, height: 190, fit: BoxFit.contain),
              const SizedBox(height: AppSpacing.lg),
              Text(title,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(message,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
