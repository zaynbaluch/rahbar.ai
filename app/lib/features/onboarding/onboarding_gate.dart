import 'package:flutter/material.dart';

import 'onboarding_screen.dart';
import 'onboarding_store.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.child,
    this.store,
  });

  final Widget child;
  final OnboardingStore? store;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late final OnboardingStore _store;
  late Future<OnboardingState> _state;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? OnboardingStore();
    _state = _store.read();
  }

  void _retry() => setState(() => _state = _store.read());

  Future<void> _reset() async {
    try {
      await _store.reset();
    } finally {
      if (mounted) _retry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingState>(
      future: _state,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storage_rounded, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Bayaz could not read setup data on this device.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                        FilledButton(
                          onPressed: _reset,
                          child: const Text('Reset setup'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data!.completed) return widget.child;
        return OnboardingScreen(
          store: _store,
          onCompleted: () {
            setState(() => _state = _store.read());
          },
        );
      },
    );
  }
}
