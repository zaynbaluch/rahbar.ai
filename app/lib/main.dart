import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'app/bayaz_shell.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preserve the project's existing model-spike runtimes. They are no longer
  // exposed in the teacher navigation, but remain available to the existing
  // internal spike code without changing its behavior.
  await FlutterGemma.initialize(
    inferenceEngines: const [MediaPipeEngine(), LiteRtLmEngine()],
  );

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
      home: const BayazShell(),
    );
  }
}
