import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'app/rahbar_shell.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preserve the project's existing model-spike runtimes. They are no longer
  // exposed in the teacher navigation, but remain available to the existing
  // internal spike code without changing its behavior.
  await FlutterGemma.initialize(
    inferenceEngines: const [MediaPipeEngine(), LiteRtLmEngine()],
  );

  runApp(const RahbarApp());
}

class RahbarApp extends StatelessWidget {
  const RahbarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rahbar AI',
      debugShowCheckedModeBanner: false,
      theme: RahbarTheme.light(),
      home: const RahbarShell(),
    );
  }
}
