# ADR-002 — On-device inference engine: flutter_gemma (LiteRT), llama.cpp as fallback

> **Status: Superseded for production runtime.** Real-device experiments selected llama.cpp through the pinned `llama_cpp_dart` dependency. This ADR is retained as historical research; see `../01-architecture.md` and `../resources/MODEL_AND_MODULE_DELIVERY.md`.


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

> **⚠️ DECISION REVERSED for budget hardware (2026-07-06, on-device test).** On the real
> target-class device (Redmi Note 12, Snapdragon 680/685, Adreno budget GPU), **flutter_gemma /
> LiteRT is NOT viable**:
> - **GPU delegate fails** — `Invalid work group size {1,1,512}` / "Failed to invoke the
>   compiled model". The budget Adreno GPU can't run LiteRT's OpenCL kernels. So LiteRT's main
>   selling point (GPU offload) is unavailable on exactly the devices we target.
> - **LiteRT CPU is too slow** — Gemma 4 E2B (`.litertlm`) ran at **~1.4 tok/s** (≈9 min for an
>   800-token lesson plan) at ~1.6 GB RAM. Quality was excellent, but the speed is unusable.
> - **llama.cpp Q4 crushes it on the same phone**: Llama 3.2 1B **7.5 tok/s @ 0.9 GB**, Qwen3
>   1.7B **6.5 tok/s @ 1.4 GB** — ~5× faster and lighter (better ARM CPU kernels + aggressive Q4).
>
> **⚠️ GPU CONFIRMED DEAD-END via a 2nd framework (2026-07-08).** To chase a ~2× speedup we
> built **llama.cpp's own Adreno OpenCL backend** (`GGML_OPENCL`, embedded kernels) for arm64 and
> ran it on-device. The Adreno **610** *is* detected and all kernels load, but:
> - The Qualcomm platform reports OpenCL 3.0 while the **device is only OpenCL 2.0** — the backend
>   hard-asserts on a 3.0-only query (`CL_DEVICE_OPENCL_C_ALL_VERSIONS`). Patched to fall back.
> - It then **fails `clEnqueueNDRangeKernel`** (GGML_ASSERT at ggml-opencl.cpp:591) during the
>   first matmul — the 610 lacks **subgroup broadcast** and has restrictive workgroup limits that
>   llama.cpp's kernels (tuned for flagship Adreno 6xx/7xx) violate. The generic (non-Adreno)
>   kernels fail the same way. This is the *same* class of failure LiteRT hit — the budget Adreno
>   simply can't run these compute kernels. **Conclusion: CPU is the only viable backend on this
>   class of device; speed work must target the CPU path (context size, quant, threads).**
>
> **New decision: `llama.cpp` / GGUF is the PRIMARY runtime for budget devices** (this ADR's
> former "fallback" and "primary" swap). Needs a Flutter FFI binding (`fllama` /
> `llama_cpp_dart`) — more integration work than flutter_gemma, but the only path fast enough.
> flutter_gemma/LiteRT stays only as an option for higher-end phones with a working GPU delegate.
> Model target narrows to **1–1.7 B Q4** (Llama 3.2 1B / Qwen3 1.7B). See [ADR-003](ADR-003-generation-model.md).
>
> **✅ WORKING ON-DEVICE (2026-07-07).** Integrated `llama_cpp_dart` v0.2.0 (vendored at
> `third_party/`, path dep; native libs built from its pinned llama.cpp submodule by
> `scripts/setup-llama.sh`, bundled in `app/.../jniLibs/`). App: `LlamaCppService` (isolate,
> CPU, streaming). **Llama 3.2 1B Q4 generates in-app at ~7.0 tok/s — matching the `llama-bench`
> prediction (7.5).** Four non-obvious fixes were required (all captured in `setup-llama.sh` /
> `llama_cpp_service.dart`), documented so we never re-debug them:
> 1. **`add_compile_definitions(GGML_USE_CPU)`** — the package's wrapper CMake set `GGML_USE_CPU`
>    only on its `mtmd` target, not on `ggml` (where `ggml-backend-reg.cpp` lives), so the CPU
>    backend was never statically registered → `llama_model_load: available devices: 0`.
> 2. **`ModelParams.mainGpu = -1`** — with 0 GPU devices (Vulkan off), the default `main_gpu=0`
>    fails llama.cpp's `main_gpu >= devices.size()` validation. `-1` skips it → CPU fallback.
> 3. **`BUILD_SHARED_LIBS=ON`** (separate libs) — static-linking into one `libmtmd.so` stripped
>    FFI-only symbols (`undefined symbol: llama_sampler_chain_init`). Separate `libllama.so`
>    exports all API symbols.
> 4. **`ANDROID_STL=c++_shared`** + bundle `libc++_shared.so`; and the app copies the GGUF from
>    FUSE external storage to internal ext4 (llama.cpp's native `open()` fails on FUSE).

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
