import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mcq_grammar.dart';

/// On-device generation via **llama.cpp** (GGUF), the primary runtime for budget
/// devices after the bake-off (see docs/decisions/ADR-002/003). Uses the vendored
/// `llama_cpp_dart` FFI binding; llama.cpp runs in its own isolate (off the UI
/// thread). CPU-only here — this budget Adreno GPU can't accelerate reliably.
///
/// Shipping model is **Qwen3 1.7B** (ChatML template) with **greedy decoding**
/// (temp 0 + repeat penalty) — the grounded-quality bake-off (ADR-003) showed
/// default temperature collapses structured MCQ output, and greedy + Qwen3 1.7B
/// gets 9/10 answer keys right vs Llama 1B's ~5/10.
class LlamaCppService {
  LlamaParent? _parent;
  String? _loadedFile;
  String? _loadedGrammar;

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
  ///
  /// [grammar] is an optional GBNF string that constrains decoding (used for the
  /// MCQ schema — see [kMcqGrammar]). The binding fixes the sampler at load time,
  /// so switching the grammar (e.g. MCQ→lesson) reloads the model. That only
  /// happens on a mode change, not per generation, so the cost is a rare one-off.
  Future<void> load(
    String fileName, {
    String? grammar,
    int nThreads = 4, // 4 big cores
    int nCtx = 4096, // room for ~2 K-token RAG prompt + generation
  }) async {
    if (_loadedFile == fileName && _loadedGrammar == grammar && _parent != null) {
      return;
    }
    await unload();

    // The Android build produces libmtmd.so (links llama + ggml).
    Llama.libraryPath = 'libmtmd.so';

    final load = LlamaLoad(
      path: await _internalModelPath(fileName), // internal ext4 — native open() works
      modelParams: ModelParams()
        ..nGpuLayers = 0 // CPU-only on budget hardware
        // main_gpu=-1 → no GPU device required (else load fails validation when
        // there are 0 GPU devices, as on this Vulkan-off CPU build).
        ..mainGpu = -1,
      contextParams: ContextParams()
        ..nCtx = nCtx
        ..nBatch = nCtx // prefill the whole RAG prompt in one batch
        ..nThreads = nThreads
        ..nThreadsBatch = nThreads,
        // NOTE: flash attention was measured on this SoC (bench) — it speeds prefill
        // ~25% but slows token generation ~18%, a net wash (worse for gen-heavy
        // lesson plans), so it stays OFF. The real lever is shrinking the RAG context
        // (see RagService context budget), which cuts prefill AND speeds gen-at-depth.
      // GREEDY decoding for structured output (see ADR-003 bake-off). temp=0 makes
      // llama.cpp's temp sampler pick argmax; penaltyRepeat curbs the small model's
      // tendency to recycle distractors. (The `greedy` flag would skip the penalty.)
      samplingParams: SamplerParams()
        ..temp = 0.0
        ..penaltyRepeat = 1.15
        // GBNF grammar (MCQ only): forces the exact parseable schema regardless
        // of the model's format discipline. Empty = unconstrained (lesson plans).
        ..grammarStr = grammar ?? ''
        ..grammarRoot = grammar == null ? '' : kMcqGrammarRoot,
      verbose: true, // surface llama.cpp's native logs (else they're silenced)
    );
    // ChatML formatter — Qwen3's template. formatMessages() wraps system+user as
    // <|im_start|>system…<|im_start|>user…<|im_start|>assistant. Tokenized with
    // parse_special=true so the control tokens are recognized.
    _parent = LlamaParent(load, ChatMLFormat());
    await _parent!.init();
    _loadedFile = fileName;
    _loadedGrammar = grammar;
  }

  /// Stream a grounded generation from a **system + user** message pair (the RAG
  /// path). Resets chat history each call so generations are independent.
  Stream<String> generateChat(String system, String user) {
    final parent = _parent;
    if (parent == null) throw StateError('No model loaded — call load() first.');
    parent.messages
      ..clear()
      ..add({'role': 'system', 'content': system})
      ..add({'role': 'user', 'content': user});
    return _stream(parent, ''); // prompt ignored when messages are set
  }

  /// Stream a plain single-prompt generation (spike / ungrounded path).
  Stream<String> generate(String prompt) {
    final parent = _parent;
    if (parent == null) throw StateError('No model loaded — call load() first.');
    parent.messages.clear(); // ensure the single-prompt (formatPrompt) path is used
    return _stream(parent, prompt);
  }

  Stream<String> _stream(LlamaParent parent, String prompt) async* {
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
    _loadedGrammar = null;
  }
}
