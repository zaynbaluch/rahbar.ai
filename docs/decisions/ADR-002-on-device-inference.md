# ADR-002 — On-device inference engine: flutter_gemma (LiteRT), llama.cpp as fallback

**Status:** Accepted (pending Week-1 spike confirmation) · **Date:** 2026-07-04

## Context

We need to run a quantized SLM (and an embedding model) inside a Flutter app, offline, on
2–4 GB RAM Android devices. The original proposal named **llama.cpp**. Since then the
landscape shifted: Google's **MediaPipe LLM Inference API is in maintenance-only mode**,
with migration recommended to **LiteRT-LM**; meanwhile the **flutter_gemma** plugin has
matured into a first-class Flutter path over LiteRT, and also exposes embeddings.

## Options considered

| Engine | Access from Flutter | Model formats | Notes |
|---|---|---|---|
| **flutter_gemma (LiteRT)** | Native plugin, maintained | `.task` / `.litertlm` | Runs Gemma 3n E2B <1.5 GB at 4-bit; supports embeddings, multimodal, function calling; Google-optimized for mobile. |
| **llama.cpp** (via Dart FFI, e.g. LlamaDart) | FFI glue needed | **GGUF** (huge model range) | Most flexible model selection; more integration work; the community standard. |
| MediaPipe LLM Inference API | Plugin/native | `.task` | **Maintenance-only**; Google steers to LiteRT-LM. Avoid as primary. |
| MLC LLM | Less Flutter-native | TVM-compiled | GPU-first (Vulkan/OpenCL); strong long-context, but heavier integration. |
| ExecuTorch | Native, less Flutter-native | ExecuTorch | Strong NPU story (QNN/MediaTek); more suited to native Kotlin. |

## Decision

**Primary: flutter_gemma on the LiteRT backend.** It is the most mature Flutter-native
route, hits our memory budget with E2B-class models, and conveniently also provides the
**on-device embedding** capability we need for RAG — one dependency covers both generation
and query embedding.

**Fallback: llama.cpp via Dart FFI (GGUF).** If we need a model that LiteRT doesn't package
well (e.g. a specific Qwen3/Llama quant), GGUF + llama.cpp gives us the widest selection at
the cost of more glue code. We keep the generation layer behind an interface so switching
engines does not ripple through the app.

## Implementation notes (verified while wiring the spike, 2026-07-05)

`flutter_gemma` 1.2.0 is **modularized**: a thin core + opt-in engine packages. You add the
engine(s) you ship and register them in `FlutterGemma.initialize(...)`:

- `flutter_gemma_mediapipe` → `MediaPipeEngine()` — runs **`.task` / `.bin`** models.
- `flutter_gemma_litertlm` → `LiteRtLmEngine()` — runs **`.litertlm`** models.
- `flutter_gemma_embeddings` → `LiteRtEmbeddingBackend()` — EmbeddingGemma/Gecko text embeddings.
- `flutter_gemma_rag_qdrant` / `flutter_gemma_rag_sqlite` → on-device vector store.

**⚠️ Android ABI reality (decisive for our emulator dev + device targeting):** the plugin
ships native prebuilts for **`arm64-v8a` only**, with ONE exception — **MediaPipe `.task`/`.bin`
text inference also runs on `x86_64`** (Google ships those ABIs in `tasks-genai`). Everything
else — **`.litertlm` (LiteRT FFI), LiteRT embeddings, vision** — is **arm64-v8a only**.

Consequences of this for us:
- On the **x86_64 emulator** (our current dev box, no KVM for arm guests) we can only run a
  **functional generation smoke test** with MediaPipe `.task` models. **`.litertlm` models
  (Qwen3, Gemma 4) and on-device embeddings cannot run there at all.**
- Real E2B-class latency/RAM **and** the RAG embedding step must be validated on a **physical
  arm64 device** (or an arm64 emulator on an Apple-Silicon host). This is the concrete reason
  the model bake-off ([ADR-003](ADR-003-generation-model.md)) and embedding validation are
  deferred to real hardware — not just a nicety.
- For production, restrict release ABIs appropriately (`abiFilters 'arm64-v8a'` if we use any
  arm64-only feature) so the Play Store never ships a broken APK to x86 devices.

**New finding — flutter_gemma bundles its own RAG stack** (EmbeddingGemma embeddings +
qdrant-edge / sqlite vector store). This overlaps [ADR-004](ADR-004-rag-stack.md); see that
ADR's revised note on whether to use it vs. raw `sqlite-vec`.

## Consequences

- Model choice is somewhat coupled to what LiteRT/MediaPipe package cleanly; the **Week-1 spike
  ([ADR-003](ADR-003-generation-model.md)) must confirm** the chosen model runs on-device
  within budget — and this must ultimately happen on **arm64 hardware**, not the x86_64 emulator.
- We design a thin `InferenceEngine` abstraction (generate + embed) so MediaPipe vs LiteRT-LM
  vs llama.cpp is an implementation detail. Implemented as `InferenceService`
  (`app/lib/features/generation/inference_service.dart`).
- Avoid building on the MediaPipe LLM API directly given its maintenance status.
- **AGP pinned to 8.11.1** (not the scaffold default 9.0.1): `flutter_gemma`'s transitive
  `background_downloader` still applies the classic Kotlin Gradle Plugin, which AGP 9's
  built-in-Kotlin rejects. 8.11.1 is the compatible sweet spot for all current deps.

## Sources

- LiteRT / MediaPipe migration + Android LLM guide: <https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference/android>
- Engine comparison (MediaPipe/llama.cpp/ExecuTorch): <https://meetprajapati.com/blogs/running-on-device-ai-models-android-mediapipe-llamacpp-executorch/>
- On-device LLM mobile guide 2026: <https://www.buildmvpfast.com/blog/on-device-llm-mobile-llama-ios-android-2026>
- flutter_gemma package: <https://pub.dev/packages/flutter_gemma> · <https://github.com/DenisovAV/flutter_gemma>
- LlamaDart (llama.cpp on Flutter): <https://blog.redlinesoft.net/posts/on-device-intelligence-flash-flutter/>
