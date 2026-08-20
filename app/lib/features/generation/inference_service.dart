import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'spike_models.dart';

/// Thin wrapper around flutter_gemma — the single seam the rest of the app talks
/// to for on-device generation (see docs/decisions/ADR-002). Supports both
/// network `.task` models and USB-pushed local `.litertlm` files, on CPU or GPU.
class InferenceService {
  InferenceModel? _model;
  String? _loadedKey;

  String? get loadedKey => _loadedKey;
  bool get isLoaded => _model != null;

  /// Resolve a model's local file path in the app's external files dir.
  Future<String?> localPath(SpikeModel m) async {
    if (m.localFile == null) return null;
    final dir = await getExternalStorageDirectory();
    return dir == null ? null : p.join(dir.path, m.localFile!);
  }

  /// Download (network) or register (local file) the model if not present.
  Future<void> ensureInstalled(
    SpikeModel m, {
    required void Function(int percent) onProgress,
  }) async {
    final alreadyThere = await FlutterGemma.isModelInstalled(m.filename);
    // Route to the right engine: `.litertlm` → LiteRT-LM, `.task` → MediaPipe.
    final fileType = m.format == ModelFormat.litertlm
        ? ModelFileType.litertlm
        : ModelFileType.task;
    var builder =
        FlutterGemma.installModel(modelType: m.modelType, fileType: fileType);

    final path = await localPath(m);
    if (path != null) {
      builder = builder.fromFile(path); // USB-pushed local file
    } else {
      builder = builder.fromNetwork(m.url!);
    }

    if (alreadyThere) {
      await builder.install();
    } else if (path != null) {
      await builder.install(); // local install has no download progress
    } else {
      await builder.withProgress(onProgress).install();
    }
  }

  /// Load the active model. [backend] picks CPU vs GPU (GPU only usable for
  /// `.litertlm` on a real arm64 device). [maxTokens] is the context window.
  Future<void> load(
    SpikeModel m, {
    required PreferredBackend backend,
    int maxTokens = 2048,
  }) async {
    final key = '${m.id}/${backend.name}';
    if (_loadedKey == key && _model != null) return;
    await unload();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: backend,
    );
    _loadedKey = key;
  }

  /// Stream generated tokens for [prompt].
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
    _loadedKey = null;
  }
}
