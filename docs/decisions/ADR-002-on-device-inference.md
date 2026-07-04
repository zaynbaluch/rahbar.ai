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

## Consequences

- Model choice is somewhat coupled to what LiteRT packages cleanly; the **Week-1 spike
  ([ADR-003](ADR-003-generation-model.md)) must confirm** the chosen model runs on-device
  within budget via flutter_gemma. If not, we fall back to GGUF/llama.cpp.
- We design a thin `InferenceEngine` abstraction (generate + embed) so LiteRT vs llama.cpp
  is an implementation detail.
- Avoid building on the MediaPipe LLM API directly given its maintenance status.

## Sources

- LiteRT / MediaPipe migration + Android LLM guide: <https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference/android>
- Engine comparison (MediaPipe/llama.cpp/ExecuTorch): <https://meetprajapati.com/blogs/running-on-device-ai-models-android-mediapipe-llamacpp-executorch/>
- On-device LLM mobile guide 2026: <https://www.buildmvpfast.com/blog/on-device-llm-mobile-llama-ios-android-2026>
- flutter_gemma package: <https://pub.dev/packages/flutter_gemma> · <https://github.com/DenisovAV/flutter_gemma>
- LlamaDart (llama.cpp on Flutter): <https://blog.redlinesoft.net/posts/on-device-intelligence-flash-flutter/>
