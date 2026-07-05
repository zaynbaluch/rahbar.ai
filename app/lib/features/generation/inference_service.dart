import 'package:flutter_gemma/flutter_gemma.dart';

import 'spike_models.dart';

/// Thin wrapper around flutter_gemma — the single seam the rest of the app
/// talks to for on-device generation (see docs/decisions/ADR-002). Keeping the
/// engine behind this interface means swapping MediaPipe ↔ LiteRT-LM, or the
/// final model, never ripples into feature code.
class InferenceService {
  InferenceModel? _model;
  String? _loadedModelId;

  String? get loadedModelId => _loadedModelId;
  bool get isLoaded => _model != null;

  /// Download + register the model if not already present. [onProgress] gets
  /// 0..100 during a network download; skipped entirely if already installed.
  Future<void> ensureInstalled(
    SpikeModel m, {
    required void Function(int percent) onProgress,
    String? hfToken,
  }) async {
    final alreadyThere = await FlutterGemma.isModelInstalled(m.filename);
    final builder = FlutterGemma.installModel(modelType: m.modelType)
        .fromNetwork(m.url, token: hfToken);
    if (alreadyThere) {
      // File is on disk — this only (re)sets it as the active model; no download.
      await builder.install();
    } else {
      await builder.withProgress(onProgress).install();
    }
  }

  /// Load the active model into memory. On the x86_64 emulator we force CPU —
  /// GPU/NPU backends are unavailable there (see ADR-002/003). [maxTokens] is
  /// the context window (input + output), not the reply length.
  Future<void> load(SpikeModel m, {int maxTokens = 1024}) async {
    if (_loadedModelId == m.id && _model != null) return;
    await unload();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.cpu,
    );
    _loadedModelId = m.id;
  }

  /// Stream generated tokens for [prompt]. Yields text chunks as they arrive so
  /// the UI can render progressively and we can measure real latency.
  Stream<String> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 512,
  }) async* {
    final model = _model;
    if (model == null) {
      throw StateError('No model loaded — call load() first.');
    }
    final chat = await model.createChat(
      maxOutputTokens: maxOutputTokens,
      systemInstruction: systemInstruction,
    );
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        yield response.token;
      }
    }
  }

  Future<void> unload() async {
    await _model?.close();
    _model = null;
    _loadedModelId = null;
  }
}
