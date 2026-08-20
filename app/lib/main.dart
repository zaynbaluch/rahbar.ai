import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'core/theme.dart';
import 'features/generation/model_spike_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register the on-device inference engine(s). MediaPipe runs `.task` text
  // inference and is the only path that works on the x86_64 emulator (see
  // docs/decisions/ADR-002). On a physical arm64 device we'll also add
  // LiteRtLmEngine (.litertlm) and the embeddings backend for RAG.
  await FlutterGemma.initialize(
    inferenceEngines: const [MediaPipeEngine()],
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
      home: const ModelSpikeScreen(),
    );
  }
}
