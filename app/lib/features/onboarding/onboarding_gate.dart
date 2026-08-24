import 'package:flutter/material.dart';

import 'onboarding_screen.dart';
import 'onboarding_store.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  final _store = OnboardingStore();
  late Future<OnboardingState> _state;

  @override
  void initState() {
    super.initState();
    _state = _store.read();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingState>(
      future: _state,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data!.completed) return widget.child;
        return OnboardingScreen(
          onCompleted: () {
            setState(() => _state = _store.read());
          },
        );
      },
    );
  }
}
