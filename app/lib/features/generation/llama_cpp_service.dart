import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-device generation via **llama.cpp** (GGUF), the primary runtime for budget
/// devices after the bake-off (see docs/decisions/ADR-002/003). Uses the vendored
/// `llama_cpp_dart` FFI binding; llama.cpp runs in its own isolate (off the UI
/// thread). CPU-only here — this budget Adreno GPU can't accelerate reliably.
class LlamaCppService {
  LlamaParent? _parent;
  String? _loadedFile;

  bool get isLoaded => _parent != null;

  /// llama.cpp opens the model with a native `open()`, which is blocked on
  /// Android's FUSE-emulated external storage (SELinux). So we copy the
  /// USB-pushed model from the external dir into internal storage (real ext4)
  /// on first use, and load llama.cpp from there. The Dart copy works where the
  /// native open() doesn't.
  Future<String> _internalModelPath(String fileName) async {
    final ext = await getExternalStorageDirectory();
    final internal = await getApplicationSupportDirectory();
    final src = File(p.join(ext!.path, fileName));
    final dst = File(p.join(internal.path, fileName));
    final needCopy = !await dst.exists() ||
        (await dst.length()) != (await src.length());
    if (needCopy) {
      await src.copy(dst.path);
    }
    return dst.path;
  }

  /// Load a GGUF from the app's external files dir (USB-pushed).
  Future<void> load(
    String fileName, {
    int nThreads = 4, // 4 big cores
    int nCtx = 2048,
  }) async {
    if (_loadedFile == fileName && _parent != null) return;
    await unload();

    // The Android build produces libmtmd.so (links llama + ggml).
    Llama.libraryPath = 'libmtmd.so';

    final load = LlamaLoad(
      path: await _internalModelPath(fileName), // internal ext4 — native open() works
      modelParams: ModelParams()..nGpuLayers = 0, // CPU-only on budget hardware
      contextParams: ContextParams()
        ..nCtx = nCtx
        ..nThreads = nThreads
        ..nThreadsBatch = nThreads,
      samplingParams: SamplerParams(),
    );
    _parent = LlamaParent(load);
    await _parent!.init();
    _loadedFile = fileName;
  }

  /// Stream generated tokens; completes when the model signals done.
  Stream<String> generate(String prompt) async* {
    final parent = _parent;
    if (parent == null) throw StateError('No model loaded — call load() first.');

    final out = StreamController<String>();
    final tokenSub = parent.stream.listen(out.add);
    final doneSub = parent.completions.listen((_) {
      if (!out.isClosed) out.close();
    });

    unawaited(parent.sendPrompt(prompt)); // fire; tokens arrive via stream
    try {
      yield* out.stream;
    } finally {
      await tokenSub.cancel();
      await doneSub.cancel();
    }
  }

  Future<void> unload() async {
    await _parent?.dispose();
    _parent = null;
    _loadedFile = null;
  }
}
