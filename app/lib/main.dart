import 'package:flutter/material.dart';

import 'app/bayaz_shell.dart';
import 'core/theme.dart';
import 'features/onboarding/onboarding_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BayazApp());
}

class BayazApp extends StatelessWidget {
  const BayazApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bayaz AI',
      debugShowCheckedModeBanner: false,
      theme: BayazTheme.light(),
      home: const OnboardingGate(child: BayazShell()),
    );
  }
}
