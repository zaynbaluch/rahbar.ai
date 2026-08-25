import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class RecoveredDataNotice extends StatelessWidget {
  const RecoveredDataNotice({
    super.key,
    required this.count,
    required this.itemLabel,
  });

  final int count;
  final String itemLabel;

  @override
  Widget build(BuildContext context) {
    final plural = count == 1 ? itemLabel : '${itemLabel}s';
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$count unreadable $plural could not be loaded and was moved aside. Your remaining data is safe.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
