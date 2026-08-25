import 'package:flutter/material.dart';

import '../settings/settings_screen.dart';
import 'offline_ai_policy.dart';

Future<T?> openOfflineAiScreen<T>(
  BuildContext context,
  WidgetBuilder builder, {
  OfflineAiPolicy? policy,
}) async {
  final enabled = await (policy ?? OfflineAiPolicy()).isEnabled();
  if (!context.mounted) return null;
  if (enabled) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: builder),
    );
  }

  final reviewSetup = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Offline AI is turned off'),
      content: const Text(
        'Custom generation and Ask Bayaz are disabled. You can enable them in teacher setup without downloading the models again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
  if (reviewSetup == true && context.mounted) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }
  return null;
}
