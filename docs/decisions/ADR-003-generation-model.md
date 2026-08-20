# ADR-003 — Generation model: shortlist → on-device spike → pick

**Status:** Proposed (decision finalized after Week-1 spike) · **Date:** 2026-07-04

> **Spike checkpoint (2026-07-05) — integration proven, model choice still open.**
> The generation pipeline runs **end-to-end inside the Rahbar AI app** on the x86_64
> emulator: pick model → download (`.task`) → load (MediaPipe, CPU) → **stream tokens** →
> render. Smoke-tested with **SmolLM 135M** on the plant-cell MCQ prompt — coherent,
> on-topic output; ~978 token-chunks in ~15.7 s (**~62 chunks/s**). Caveats: (1) this is
> **x86_64 emulator CPU**, *not* a real budget-phone number — meaningless for perf ranking;
> (2) SmolLM over-generated (ignored "2 questions") — expected at 135M; (3) output is
> **ungrounded** (no RAG yet). The real Gemma 3n E2B / Qwen bake-off still needs **arm64
> hardware** (`.litertlm` + embeddings are arm64-only — see [ADR-002](ADR-002-on-device-inference.md)).
> Harness: `app/lib/features/generation/` (`model_spike_screen.dart`, `inference_service.dart`,
> `spike_models.dart`).

> **On-device bake-off results (2026-07-06) — real budget hardware.**
> Device: **Xiaomi Redmi Note 12 (23021RAAEG)** — Snapdragon 680/685-class budget SoC
> (4× Cortex-A73 @2.8 GHz + 4× A53 @1.9 GHz, **ARMv8.0 — no dotprod/i8mm**), 8 GB RAM,
> connected via USB. Measured with **llama.cpp (`llama-bench`, Q4_K_M, 4 threads)** as a
> level-field CPU baseline (harness in `/run/media/zayn/Personal/llamacpp-bench/`):
>
> | Model | Peak RAM (RSS) | Prefill t/s | Gen t/s | Budget fit (2–4 GB) |
> |---|---|---|---|---|
> | Llama 3.2 **1B** | **0.9 GB** | 11.5 | 7.5 | ✅ comfortable |
> | Qwen3 **1.7B** | **1.4 GB** | 10.0 | 6.5 | ✅ ok |
> | Llama 3.2 **3B** | 2.1 GB | 5.0 | 3.2 | ⚠️ too tight |
> | Qwen3 **4B** | 2.6 GB | 3.9 | 2.4 | ❌ no |
>
> **Conclusions:** (1) **RAM eliminates 3B/4B** for budget devices — DECISION: drop them.
> (2) **CPU inference is too slow** — prefill ≈ generation speed (no dotprod on A73), so a
> ~1,200-token RAG prompt + ~800-token lesson plan ≈ **3.5 min on CPU for even the 1B**.
> (3) Therefore the product path is **LiteRT + Adreno GPU via flutter_gemma**, not CPU. These
> llama.cpp numbers are a fair *screening* baseline, not the app's runtime.
>
> **In-app LiteRT test of Gemma 4 E2B (2026-07-06) — great quality, unusable speed.**
> Loaded the ungated `.litertlm` in the app on the real device (USB-pushed, `fromFile`,
> `fileType: litertlm`). Results:
> - **Quality: excellent** — correct, well-formatted MCQs; followed instructions (unlike the
>   135M smoke model). Gemma 4 E2B is genuinely capable.
> - **GPU: failed** (Adreno budget GPU — see [ADR-002](ADR-002-on-device-inference.md)).
> - **CPU: ~1.4 tok/s, ~1.6 GB RAM (clean peak)** — ≈9 min for an 800-token plan. Unusable.
>
> **Decision (2026-07-06): drop LiteRT + the 2 B Gemma for budget devices; pivot to
> llama.cpp/GGUF with a 1–1.7 B Q4 model** (Llama 3.2 1B @ 7.5 tok/s / Qwen3 1.7B @ 6.5 tok/s
> — the fastest viable options measured). Next: (a) integrate an llama.cpp Flutter FFI binding,
> (b) verify 1–1.7 B **quality** with RAG grounding is good enough, (c) design UX around
> ~1.5–2 min generation (progress / background / save-and-reuse).

> **✅ GROUNDED-QUALITY BAKE-OFF (2026-07-07) — model DECIDED: Qwen3 1.7B.**
> Ran the real RAG pipeline end-to-end on-device: retrieved the top-6 curriculum excerpts for
> topic *"the human digestive system"* from `curriculum.db`, filled the MCQ template
> (`prompts/mcq.md`), and generated a full 10-question test via `llama-cli` on the Redmi Note 12
> (harness: `pipeline/src/make_test_prompt.py` emits the grounded prompt; `sys.txt`/`usr.txt`
> pushed to `/data/local/tmp`). Both models Q4_K_M, greedy, 4 threads, `-c 4096`, `-st`.
>
> | Model | Config | Format | Answer-key accuracy | Variety | Gen t/s (w/ 2 K-tok RAG ctx) |
> |---|---|---|---|---|---|
> | Llama 3.2 **1B** | temp 0.8 (default) | **collapsed** — empty Qs, template placeholders leak, textbook lines pasted as "questions" | — | — | 4.5 |
> | Llama 3.2 **1B** | **temp 0 (greedy)** | ✅ 10 well-formed Qs | ❌ **~5/10 wrong** — shuffles 4 option-templates across organs, mis-assigns (bile "kills germs", pancreas key wrong); repetitive distractors | poor (Q1≈Q6) | 4.1 |
> | Qwen3 **1.7B** | temp 0, `/no_think` | ✅ 10 Qs **+ `KEY:` line** | ✅ **9/10 correct** (only Q5 "all of the above" debatable) | ✅ varied, precise | 3.3 |
>
> **Three findings, all decisive:**
> 1. **Greedy decoding is MANDATORY for structured output.** At temp 0.8 the 1B model *collapses*
>    (empty questions, literal `<question text>` placeholders, textbook sentences pasted as
>    questions). At temp 0 the *same* model produces 10 clean questions. → App must set
>    `SamplerParams` to greedy/low-temp for generation. This was the single biggest quality lever.
> 2. **RAG grounding works** — both models stayed strictly on the retrieved digestive-system
>    excerpts (bile→liver, amylase/protease/lipase, diarrhoea/ORS); no off-topic hallucination.
>    The retrieval + prompt assembly (`rag_prompt.py`) is validated.
> 3. **Llama 3.2 1B is NOT good enough; Qwen3 1.7B IS.** Even greedy, the 1B mis-assigns ~half the
>    answer keys (unsafe for a teacher to use blind) and repeats questions. Qwen3 1.7B gets 9/10
>    keys right, covers varied concepts, and is genuinely teacher-usable.
>
> **DECISION: ship Qwen3 1.7B Q4_K_M** as the generation model (Llama 3.2 1B stays only as a
> low-RAM fallback). **Cost:** Qwen3 gen ≈ **3.3 tok/s** and the **~2 K-token RAG prefill @ 9.4 t/s
> dominates** → **~5–6 min for a full 10-MCQ test** on this budget SoC (llama-bench's context-free
> 6.5 t/s overstates real speed once a big RAG context fills the KV cache). Mitigations to pursue:
> trim retrieval (k=6→k=4, shorter excerpts) to cut prefill; single-topic/shorter generations;
> UX around a multi-minute run (progress + background + save-and-reuse). Next: set greedy sampling
> in `LlamaCppService`, swap the app's bundled model to Qwen3 1.7B, and wire on-device RAG retrieval.

## Context

The generation model must produce credible, curriculum-grounded **lesson plans and MCQs**
while fitting in **2–4 GB RAM** and generating at usable speed **on-device**. The original
proposal suggested "Gemma 4" or "Qwen 3.5B"; the accurate 2026 equivalents are **Gemma 3n
E2B** and **Qwen3 1.7B/4B**. A 4B model at Q4 (~2.5–3 GB) is unrealistic once OS + app +
KV-cache overhead is counted on a 2–4 GB device, so we target the **~1–2B effective** class.

Encouragingly, recent literature shows **RAG-grounded small models rival much larger ones**
for educational MCQ/content generation — careful RAG + prompting compensates for size. So a
small model is a legitimate, not merely tolerable, choice.

## Shortlist

| Model | Effective size | Footprint (Q4) | Why shortlisted |
|---|---|---|---|
| **Gemma 3n E2B** | ~2B effective | **<1.5 GB via LiteRT** (2/4-bit) | Purpose-built for phones; pairs with EmbeddingGemma; first-class in flutter_gemma. |
| **Qwen3 1.7B** | 1.7B | ~1–1.3 GB | Strong reasoning for its size; Apache-2.0; available as GGUF. |
| **Llama 3.2 1B / 3B** | 1B / 3B | ~0.8 GB / ~2 GB | Well-benchmarked; 3B (63.4% MMLU) if RAM allows, 1B as safe floor. |

Excluded: Phi-4-mini (~3.8B, likely too big), SmolLM (quality risk for structured
pedagogical output).

## Decision (provisional)

**Start with Gemma 3n E2B via flutter_gemma**, and run a **head-to-head Week-1 spike** on a
real 2–4 GB device against Qwen3 1.7B and Llama 3.2 1B/3B. Pick the winner on measured:

- **Peak RAM** (must leave headroom; target <~2 GB peak).
- **Latency / tokens-per-sec** for a representative lesson plan + 10-MCQ generation
  (budget-Android CPU inference is realistically ~5–10 tok/s).
- **Output quality** — correctness, curriculum fit, MCQ plausibility (blind review, see
  [`../06-rag-quality-plan.md`](../06-rag-quality-plan.md)).
- **Cold-start** time and battery for one generation.

## Consequences

- The generation layer stays behind the `InferenceEngine` interface ([ADR-002](ADR-002-on-device-inference.md))
  so the final pick is swappable.
- If even E2B is too heavy on the low end (2 GB devices), fall back to Llama 3.2 1B or a
  more aggressive quant, accepting some quality loss offset by stronger RAG.
- Record the spike results back into this ADR to move it to **Accepted**.

## Sources

- SLMs for Android 2026 / Gemma 3n E2B footprint: <https://localaimaster.com/blog/small-language-models-guide-2026> · <https://www.bentoml.com/blog/the-best-open-source-small-language-models>
- Small model + RAG rivals large models (education): <https://arxiv.org/pdf/2506.05925> · <https://dl.acm.org/doi/10.1145/3641554.3701844>
- RAG-enhanced MCQ generation: <https://sol.sbc.org.br/index.php/sbie/article/view/38499>
- Gemma model overview: <https://ai.google.dev/gemma/docs/core>
