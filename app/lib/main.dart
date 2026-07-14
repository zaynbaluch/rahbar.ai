import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'core/theme.dart';
import 'features/content/topic_picker_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register on-device inference engines. MediaPipe runs `.task` models (works on
  // x86_64 emulator + arm64); LiteRT-LM runs `.litertlm` models (arm64 device only,
  // GPU-capable) — the path for our mobile-optimized Gemma candidate. See ADR-002/003.
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
      // Home is the curriculum topic picker, served from the pre-generated content pack
      // (ADR-008). The on-device SLM (GenerationScreen) is reachable from it as the
      // escape hatch for topics the pack does not cover.
      home: const TopicPickerScreen(),
    );
  }
}
