import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_spacing.dart';
import '../settings/settings_screen.dart';
import 'offline_ai_policy.dart';

class OfflineAiGate extends StatefulWidget {
  const OfflineAiGate({
    super.key,
    required this.title,
    required this.enabledBuilder,
    this.policy,
    this.openSettings,
  });

  final String title;
  final WidgetBuilder enabledBuilder;
  final OfflineAiPolicy? policy;

  /// Opens teacher setup. Overridden by tests so they do not have to drive the
  /// real settings screen and its file-backed store.
  final Future<void> Function(BuildContext context)? openSettings;

  @override
  State<OfflineAiGate> createState() => _OfflineAiGateState();
}

class _OfflineAiGateState extends State<OfflineAiGate> {
  late OfflineAiPolicy _policy;
  late Future<bool> _enabled;

  @override
  void initState() {
    super.initState();
    _policy = widget.policy ?? OfflineAiPolicy();
    _enabled = _policy.isEnabled();
  }

  @override
  void didUpdateWidget(covariant OfflineAiGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy != widget.policy) {
      _policy = widget.policy ?? OfflineAiPolicy();
      _enabled = _policy.isEnabled();
    }
  }

  Future<void> _openSettings() async {
    final open = widget.openSettings;
    if (open != null) {
      await open(context);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
    if (!mounted) return;
    setState(() {
      _enabled = _policy.isEnabled();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _enabled,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: BayazCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not read the offline AI setting.'),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _enabled = _policy.isEnabled();
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.data == true) return widget.enabledBuilder(context);

        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: BayazCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.offline_bolt_outlined, size: 44),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Offline AI is turned off',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Custom generation and clarification chat stay unavailable until you enable them in teacher setup. Existing downloads are kept.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
