import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'generation_stream_bridge.dart';
import 'lfm2_prompt_format.dart';
import 'mcq_grammar.dart';

/// On-device generation via **llama.cpp** (GGUF), the primary runtime for budget
/// devices after the bake-off (see docs/decisions/ADR-002/003). Uses the vendored
/// `llama_cpp_dart` FFI binding; llama.cpp runs in its own isolate (off the UI
/// thread). CPU-only here — this budget Adreno GPU can't accelerate reliably.
///
/// The current model profile is Liquid AI LFM2 1.2B in GGUF form with greedy
/// decoding (temperature 0 plus repeat penalty). The model-specific formatter
/// preserves LFM2's published start-of-text and role tokens while all generation
/// stays on-device.
class LlamaCppService {
  LlamaParent? _parent;
  String? _loadedFile;
  String? _loadedGrammar;
  bool _generationActive = false;
  Completer<void>? _generationDone;
  Future<void> _lifecycleTail = Future<void>.value();

  bool get isLoaded => _parent != null;

  /// Load a model already installed in private app storage by ResourceManager.
  Future<void> loadPath(
    String modelPath, {
    String? grammar,
    int nThreads = 4,
    int nCtx = 4096,
  }) =>
      _enqueueLifecycle(() => _loadPath(
            modelPath,
            grammar: grammar,
            nThreads: nThreads,
            nCtx: nCtx,
          ));

  Future<void> _loadPath(
    String modelPath, {
    String? grammar,
    required int nThreads,
    required int nCtx,
  }) async {
    final model = File(modelPath);
    if (!await model.exists()) {
      throw StateError('Local language model is not installed.');
    }
    if (_loadedFile == modelPath && _loadedGrammar == grammar && _parent != null) {
      return;
    }
    await _unloadCurrent();

    // The Android build produces libmtmd.so (links llama + ggml).
    Llama.libraryPath = 'libmtmd.so';

    final load = LlamaLoad(
      path: modelPath,
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
      // `llama_log_set` is a process-global native callback, not per-model.
      // RagService's embedder loads first and (with verbose:false) binds it to
      // its own isolate. If this load left it at verbose:true, that stale
      // cross-isolate callback pointer gets invoked when LFM2 logs during
      // load, and the Dart VM aborts with "Cannot invoke native callback
      // from a different isolate" (SIGABRT). Must stay false so this load
      // re-binds the (silent) callback to its own isolate instead.
      verbose: false,
    );
    // The pinned binding does not apply the GGUF's embedded Jinja chat template,
    // so format the published LFM2 token sequence explicitly.
    final parent = LlamaParent(load, Lfm2PromptFormat());
    _parent = parent;
    try {
      await parent.init();
      _loadedFile = modelPath;
      _loadedGrammar = grammar;
    } catch (_) {
      if (identical(_parent, parent)) {
        _parent = null;
        _loadedFile = null;
        _loadedGrammar = null;
      }
      try {
        await parent.dispose();
      } catch (_) {
        // Preserve the original load failure.
      }
      rethrow;
    }
  }

  /// Stream a grounded generation from a **system + user** message pair (the RAG
  /// path). Resets chat history each call so generations are independent.
  Stream<String> generateChat(String system, String user) {
    final parent = _parent;
    if (parent == null) throw StateError('No model loaded — call loadPath() first.');
    parent.messages
      ..clear()
      ..add({'role': 'system', 'content': system})
      ..add({'role': 'user', 'content': user});
    return _stream(parent, ''); // prompt ignored when messages are set
  }

  /// Stream a plain single-prompt generation (spike / ungrounded path).
  Stream<String> generate(String prompt) {
    final parent = _parent;
    if (parent == null) throw StateError('No model loaded — call loadPath() first.');
    parent.messages.clear(); // ensure the single-prompt (formatPrompt) path is used
    return _stream(parent, prompt);
  }

  Stream<String> _stream(LlamaParent parent, String prompt) async* {
    if (_generationActive) {
      throw StateError('A local generation is already running.');
    }
    _generationActive = true;
    final done = Completer<void>();
    _generationDone = done;
    try {
      yield* const GenerationStreamBridge().run(
        tokens: parent.stream,
        completions: parent.completions.map(
          (event) => ModelCompletion(
            promptId: event.promptId,
            success: event.success,
            errorDetails: event.errorDetails,
          ),
        ),
        start: () => parent.sendPrompt(prompt),
        stop: parent.stop,
      );
    } finally {
      _generationActive = false;
      if (!done.isCompleted) done.complete();
      if (identical(_generationDone, done)) _generationDone = null;
    }
  }

  Future<void> unload() => _enqueueLifecycle(_unloadCurrent);

  Future<void> _unloadCurrent() async {
    final parent = _parent;
    _parent = null;
    _loadedFile = null;
    _loadedGrammar = null;
    if (parent == null) return;

    if (_generationActive || parent.isGenerating) {
      try {
        await parent.stop();
      } catch (_) {
        // Disposal below remains the final safety net.
      }
      final done = _generationDone;
      if (done != null) {
        try {
          await done.future.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // The pinned binding may not emit a completion after a forced stop.
        }
      }
    }
    await parent.dispose();
  }

  Future<void> _enqueueLifecycle(Future<void> Function() action) {
    final next = _lifecycleTail.then(
      (_) => action(),
      onError: (_, _) => action(),
    );
    _lifecycleTail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
}
