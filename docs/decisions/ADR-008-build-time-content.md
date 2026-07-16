# ADR-008 — Build-time content generation: ship a verified bank, keep the SLM for the tail

**Status:** Accepted · **Date:** 2026-07-13
**Supersedes the *runtime* half of [ADR-003](ADR-003-generation-model.md)** (the model choice there still stands, for a smaller job).

## Context

[ADR-003](ADR-003-generation-model.md) ends with on-device generation *working* — LFM2 1.2B
+ GBNF grammar, verified on the Redmi Note 12 — and honest about what it costs:

- **~3.5 min** wall-clock for one 10-MCQ test (prefill 17.1 t/s, decode 6.9 t/s).
- **Back-to-back runs throttle to 2.4 t/s decode.** The *second* test a teacher generates is
  markedly slower than the first; ADR-003 flagged this as an unresolved UX follow-up.
- Quality is capped by model size. The same bake-off measured Llama 3.2 1B getting **~5/10
  answer keys wrong**, Qwen3 1.7B 9/10. We are spending our whole quality budget forcing a
  1.2B model into schema compliance.

Three things make the phone the wrong place to generate this content:

1. **Speed.** [`docs/09-open-questions.md`](../09-open-questions.md) names the demo
   wow-factor as *"instant speed"*. We ship 3.5 minutes.
2. **Quality.** A 1–2B model is the ceiling on a 2–4 GB device. That ceiling is low.
3. **Safety — the decisive one.** [ADR-007](ADR-007-assessment-and-omr.md) grades real
   student papers by looking up the stored answer key, with **no SLM and no human in the
   loop**. A hallucinated key marks 60–70 children wrong. Content generated on a phone,
   at the moment of use, **can never be reviewed before it is used**. Content generated at
   build time can be — by a second model, and by a person.

And the content barely changes: one PCTB Class-6 General Science book, 12 chapters, **88
teachable topics** (`pipeline/src/topics.py`). Teachers ask for lesson plans and tests on the
same curriculum year after year. We were re-deriving, slowly and unverifiably, on every
device, something that is nearly static.

## Decision

**Generate the content once, off-device, and ship it. Keep the on-device SLM for the tail.**

This is *cache-first, generate-on-miss* — not the removal of the AI, but a cache in front of it.

### Build time (laptop, RTX 4050 6 GB)

A **Qwen3 8B Q4_K_M** under `llama-server` (`scripts/setup-genserver.sh`) writes, per topic:

- a **bank of ~60 candidate MCQs**, over-generated so verification can be ruthless;
- **5E section variants** — 2–3 alternatives for each of the 11 sections in
  [ADR-006](ADR-006-lesson-plan-schema.md)'s schema.

Output is JSON-schema-constrained (llama.cpp compiles the schema to GBNF — the same mechanism
as the app's `mcq_grammar.dart`), so format is guaranteed and the prompts can spend their words
on pedagogy instead of hand-holding a small model through a text layout.

**Vulkan, not CUDA.** llama.cpp ships no prebuilt Linux CUDA binary, and building from source
needs the CUDA toolkit, which needs root. The Vulkan build runs on the NVIDIA driver that is
already present — no toolkit, no sudo — at **28.7 tok/s decode** with all 36 layers offloaded
(5.2 GB of the card's 6.1 GB, using flash-attention and a q8_0 KV cache to fit). Perhaps 10–20%
slower than CUDA, which is irrelevant for a one-off overnight run.

Measured: **~6 min/topic**, so ~8.5 h for all 88.

### Verification is what makes an 8B safe (not optional)

An 8B is a large step up from 1.2B but is **not** frontier, and it is writing answer keys that
get marked without review. Every candidate passes three gates:

1. **Structural** (free, no GPU): duplicate/empty options, "All of the above", negative stems,
   options that are *commentary* rather than answers, and **prompt-scaffolding leakage** — a
   stem reading "according to the excerpts provided" would otherwise print on a child's paper.
2. **LLM judge, in a separate call.** Judging one question against the source is a far easier
   task than inventing one, which is exactly why it catches real errors. Verdicts: `correct`
   (ship), `unsure` (**held back** for human review), `wrong` (reject).
3. **Embedding dedup** (bge-small, cosine > 0.92) so a sampled test never repeats itself —
   ADR-003 saw the on-device 1B emit Q1 ≈ Q6; the bank must not have that baked in.

Only `passed` items enter the pack. `data/processed/content/review.html` is the human
spot-check report that ADR-006 and the 3-week plan already call for.

**It works.** On the very first topic the judge caught a genuine key error the 8B had written
(*"the marked answer is wrong; both A and B are correct functions of hydrochloric acid"*) — an
item that, unverified, would have been printed and marked against a class. The structural gate
independently caught two failures that no model-quality improvement would have fixed: stems
reading *"according to the excerpts provided"* (the student never sees the excerpts), and
`materials` lists containing citations (*"Ch 4, 4.1.2 Alimentary Canal"*) instead of objects.

**Bank size is bounded by the source, not the budget.** A thin section (4.1 Digestion, ~1.8k
chars) saturates at ~20 distinct sensible questions and then the model simply repeats itself —
so `N_CANDIDATES` is 45, and over-generating further buys duplicates, not variety. Rich sections
(Solutions, Alimentary Canal) yield far more from the same budget. Dedup runs *before* the LLM
judge, so no GPU time is spent verifying a question that is about to be discarded.

### Run time (phone)

- **MCQ tests are *sampled*, not generated.** ~50 verified items per topic, sample 10 with a
  difficulty mix and an exclusion list. Instant, and effectively unlimited distinct papers.
  This is how professional assessment actually works: an item bank plus sampling.
- **Lesson plans are *assembled*, not generated.** One variant per 5E section → 50+ distinct
  plans per topic, and *"give me a different activity"* becomes a **swap**, not a regeneration.
- **The SLM keeps two jobs**: short open-ended chat/rewrite ("explain this in simpler words",
  "another analogy") — ~250 tokens, no grammar, ~20–40 s — and an **escape hatch** for topics
  outside the bank, backgrounded, using the existing grammar-constrained path unchanged.

**The rule that makes this work: the SLM must never re-emit a long structured artifact.**
Modification *is* regeneration, and regeneration is 3.5 minutes. Precomputing along the axes
teachers actually vary turns "modify" into "select".

## Consequences

- **Everything downstream is untouched.** `McqTest` → `mcq_test_view` → `PdfExport` →
  `OmrTemplate` → `omr_grader` → `gradebook_store` all consume the same objects. We swapped the
  *producer*, not the pipeline. The lesson-plan loop had no data model or PDF path at all, so
  building it bank-backed is net-new work, not rework.
- **Two invariants protect variant-swapping**, and both are enforced, not hoped for:
  *materials belong to the activity* (so swapping the Explore activity can't leave a stale
  shopping list), and *minutes live in code* (`PLAN_MINUTES`), so no swap can overrun the
  50-minute period.
- **We now own the content.** A wrong key is our fault, shipped to everyone. This is a real new
  burden — and still strictly better than an unreviewable key generated on a phone.
- **The thermal-throttling follow-up from ADR-003 is closed** for the happy path: nothing
  long-running executes on the device.
- **Distribution barely changes.** The pack is a few MB next to a 698 MB GGUF. It is versioned
  (`meta.pack_version`) so it can be replaced without an app release.
- **"Where's the AI, you shipped a database?"** — expect this. The answer only holds if the
  escape hatch genuinely works, so it stays demoable.

## Crash-safety (the run is unattended and multi-hour)

Checkpointed per `(stage, topic)` in `pipeline/src/checkpoint.py`, mirroring the resume idiom
`src/parse.py` already uses for the 2-hour Docling pass:

- one file per unit, written **atomically** (temp file + `os.replace` + `fsync`), so a power
  cut leaves either the old file or the new one, never a truncated one a resume would trust;
- a unit that exists but does not **parse** is discarded and redone — corruption self-heals;
- a failed LLM call leaves the checkpoint **unwritten**, so the unit is retried rather than
  half-saved;
- `manifest.jsonl` is for reporting only — the **files are the source of truth**;
- the pack is built by a **separate, idempotent** step, so an interrupted generation can never
  corrupt the shipped asset.

## Alternatives considered

| Option | Why not |
|---|---|
| Keep generating on-device, optimise harder | Only a faster model or fewer tokens cuts decode (ADR-003). We already took both. 3.5 min is the floor, and it leaves the answer keys unverifiable. |
| Frontier API for the bank | Better quality, trivial cost — but the laptop 8B + verification clears the bar for Grade-6 science, and keeps the whole toolchain local and reproducible. |
| Drop the SLM entirely | Removes 698 MB and the thermal problem, but guts the "offline generative AI on a budget phone" differentiation, and nothing then handles "my students struggled with X last week". |
| Precompute whole lesson plans (N variants) | Simpler, but "swap one activity" becomes impossible and every teacher gets one of only N identical plans. |
