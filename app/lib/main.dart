import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'core/theme.dart';
import 'features/generation/generation_screen.dart';

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
      home: const GenerationScreen(),
    );
  }
}
