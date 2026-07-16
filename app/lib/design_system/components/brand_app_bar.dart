import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class BrandAppBarTitle extends StatelessWidget {
  const BrandAppBarTitle({super.key, this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Image.asset('assets/ui/branding/rahbar_mark.png', width: 38, height: 38),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rahbar AI', style: theme.textTheme.titleLarge),
              if (subtitle != null)
                Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
