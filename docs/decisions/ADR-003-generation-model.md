# ADR-003 — Generation model: shortlist → on-device spike → pick

**Status:** Accepted (on-device verified 2026-07-13) · **Date:** 2026-07-04

> **⚠️ Scope narrowed by [ADR-008](ADR-008-build-time-content.md) (2026-07-13).** Everything
> below still holds — LFM2 1.2B + grammar is the right on-device model — but it is no longer
> what generates lesson plans and tests. The ~3.5 min wall-clock and the back-to-back thermal
> throttling recorded here are precisely why: **that content is now generated once at build
> time by an 8B on the laptop, verified, and shipped** (`pipeline/src/gen_content.py`). The
> on-device SLM keeps two jobs — short open-ended chat/rewrite, and an escape hatch for topics
> outside the shipped bank. The thermal-pacing follow-up flagged below is closed for the happy
> path: nothing long-running runs on the phone any more.

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

> **⚡ SPEED BAKE-OFF (2026-07-10) — model RE-DECIDED: LFM2 1.2B + grammar-constrained MCQ.**
> Qwen3 1.7B's ~3.3 tok/s decode made a full run **4–5 min in-app** — teachers won't wait. Since
> **only a faster model or fewer tokens cuts decode** (caching can't), we re-ran the bake-off with
> Liquid AI's **LFM2** (hybrid conv-attention, built for on-device CPU). Quality is
> hardware-independent, so this half ran locally on x86 against the *real* grounded prompts
> (`pipeline/src/dump_prompts.py` → same bge retrieval, k=6, char budget as the app); tok/s are
> x86 (relative ranking transfers, absolute numbers don't).
>
> | Model | Decode t/s (x86) | vs Qwen3 | Prefill t/s (x86) | vs Qwen3 | MCQ schema, unaided |
> |---|---|---|---|---|---|
> | Qwen3 1.7B | ~28 | 1.0× | ~184 | 1.0× | **10/10 Qs, 10/10 ANSWER, 10/10 difficulty tags** |
> | **LFM2 1.2B** | ~58 | **2.05×** | ~263 | **1.43×** | 8.5/10 Qs, 8.5 ANSWER, 1.8 difficulty tags |
> | LFM2 700M | ~82 | 2.9× | ~415 | 2.25× | 5.8/10 Qs, 2.0 ANSWER — too unreliable |
>
> **Findings:** (1) LFM2 1.2B confirms Liquid's "~2× decode / ~1.4× prefill vs Qwen3" on CPU, and
> its conv layers should degrade *less* than attention as the RAG KV cache fills (where Qwen3 fell
> to 3.3). (2) LFM2's **content** is good on well-covered topics but its **format discipline** is
> weaker (drops difficulty tags, sometimes <10 Qs), which would break the OMR key the app rebuilds
> from ANSWER lines. (3) **Grammar-constrained decoding (GBNF) fixes this completely** — forcing the
> exact `Qn [difficulty] … ANSWER: X` schema made LFM2 1.2B emit **10/10 parseable, OMR-ready
> questions** on every topic tested, including one where it previously wandered. Grammar fixes
> *structure*, not *semantics* — residual drift on thin-retrieval topics (e.g. photosynthesis) is a
> RAG-coverage problem that hits any model. (4) 700M is too unreliable even with grammar-worthy
> speed; keep as an experimental low-RAM option only.
>
> **DECISION: ship LFM2 1.2B Q4_K_M** with **grammar-constrained MCQ decoding**
> (`app/lib/features/generation/mcq_grammar.dart`); keep **Qwen3 1.7B** as the quality-fallback
> candidate. LFM2 uses the same ChatML `<|im_start|>` template, so the existing chat path is
> unchanged (dropped the Qwen-specific `/no_think`). The pinned llama.cpp (commit `b8595b1`,
> 2025-11-09) already includes LFM2 (`src/models/lfm2.cpp`), so the committed `libmtmd.so` runs it
> with no native rebuild. **Still to verify on-device (Redmi Note 12):** real decode tok/s and
> end-to-end wall-clock vs the old ~5 min. Harness: `pipeline/src/dump_prompts.py` +
> `eval/bakeoff/` (`bakeoff.py`, `grade.py`, `gen_grammar.py`, `mcq.gbnf`).

> **✅ ON-DEVICE VERIFICATION (2026-07-13) — confirmed on Redmi Note 12.** Ran LFM2 1.2B Q4_K_M
> with the shipping grammar (`mcq.gbnf`) via `llama-cli`, sampler matched to the app exactly
> (greedy, repeat-penalty 1.15, `-c 4096`), against the same real grounded MCQ prompt used in the
> 2026-07-07 quality bake-off (digestive-system topic, ~2 K-token RAG context, pushed to
> `/data/local/tmp`).
>
> | Run | Prefill t/s | Decode t/s | Wall-clock | Output |
> |---|---|---|---|---|
> | Cold (after cooldown) | 17.1 | **6.9** | **~3.5 min** | 10/10 valid Qs, ANSWER lines, difficulty tags |
> | Back-to-back (no cooldown) | 16.0 | **2.4** | — | still 10/10 valid (grammar holds under throttle) |
>
> **Peak RSS: 0.85 GB** — comfortable on a 2–4 GB budget device.
>
> **Findings:** (1) The cold-run numbers land almost exactly on the x86 bake-off's prediction —
> decode 6.9 vs Qwen3's in-context 3.3 t/s is a **2.1× speedup** (predicted 2.05×), prefill 17.1
> vs 9.4 t/s is **1.8×**. **Wall-clock drops from ~5–6 min to ~3.5 min** for a full 10-MCQ test —
> real but smaller than the raw decode speedup alone, because prefill of the long RAG context is
> still a large fraction of total time. (2) **Grammar-constrained decoding is robust to slowdown**
> — even when decode collapsed to 2.4 t/s under thermal load, the output was still 10/10
> structurally valid; schema correctness is a property of the sampler, not of the model staying
> "on form" under heat. (3) **New risk surfaced: back-to-back generations throttle hard** — decode
> dropped ~65% (6.9→2.4 t/s) with no cooldown between two ~3.5 min runs on this budget SoC's
> sustained-load thermals. A teacher generating several tests in a row would see the *later* ones
> run markedly slower. **Product implication:** either warn/pace back-to-back generations in the
> UX, or accept and set expectations around a "first test fast, subsequent ones slower" pattern —
> not yet decided, flagging for follow-up.
>
> **ADR-003 is now Accepted** on the model choice (LFM2 1.2B + grammar); the thermal-pacing
> question is a UX follow-up, not a blocker to shipping.

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
