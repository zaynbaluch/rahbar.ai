# 07 — 3-Week Execution Plan

Full-time, single developer. Centerpiece = **on-device generation (SLM + RAG)** for
**General Science, Class 6**. Goal: a state-of-the-art, genuinely impressive offline demo.

## Week 1 — De-risk the two hardest things (in parallel)

**Track A: on-device generation spike**
- Scaffold the Flutter app; integrate **flutter_gemma**; load **Gemma 3n E2B**.
- Get a bare prompt → generation working **on a real 2–4 GB device** (not just emulator).
- Benchmark E2B vs **Qwen3 1.7B** vs **Llama 3.2 1B/3B**: peak RAM, tokens/sec, cold-start,
  battery, output quality → **pick the model** ([ADR-003](decisions/ADR-003-generation-model.md)).

**Track B: curriculum pipeline**
- Watermark cleanup → **Docling** OCR of the 153-page book; per-chapter spot-checks.
- Block typing + **VLM captioning** of figures.
- **SLO-aligned chunking** + metadata → embed with **EmbeddingGemma (256-dim)** →
  build `curriculum.db` (`sqlite-vec`), bundle into `app/assets/rag/`.

**Exit criteria:** a chosen model generates text on-device within budget; a queryable
`curriculum.db` returns relevant chunks for sample topics.

## Week 2 — RAG + generation quality + PDF export

- Wire **on-device retrieval** (query embed → `sqlite-vec` top-k, metadata-aware).
- Build the **prompt templates** for the lesson-plan schema ([ADR-006](decisions/ADR-006-lesson-plan-schema.md))
  and the **10-question mixed-difficulty MCQ** spec ([ADR-007](decisions/ADR-007-assessment-and-omr.md));
  enforce structured JSON + grounding rules; assign a `test_id` + store the answer key.
- Iterate chunking/prompts against the **eval harness** ([`06-rag-quality-plan.md`](06-rag-quality-plan.md)):
  groundedness, curriculum fit, MCQ validity, retrieval hit-rate.
- **PDF export** (`pdf`/`printing`): lesson plan, student MCQ paper, **OMR answer sheet**
  (fiducials + QR test_id), and teacher answer key.

**Exit criteria:** grounded, schema-valid **50-min** lesson plans + a printable, OMR-ready
10-MCQ test with stored answer key, generated fully offline.

## Week 3 — OMR grading + UX polish + demo hardening

- **OMR grading loop** ([ADR-007](decisions/ADR-007-assessment-and-omr.md)): capture with
  align guide → fiducial warp → decode QR → **look up answer key by `test_id`** → score →
  flag low-confidence marks → save `grading_results`. **No SLM in this path.**
- **Beautiful Material 3 UI**: topic/SLO picker → generating state → sectioned, editable
  lesson plan → MCQ view → print → **scan-to-grade** → saved library.
- Performance tuning (**instant-feel** generation, memory, graceful low-RAM behavior).
- **Demo script**, seed content, finalize docs; blind quality review (developer + ideally a teacher).

**Exit criteria:** polished, fully-offline demo: generate → print → scan-and-grade for
Class 6 General Science on a budget Android phone.

> **Scope note:** adding PDF export + OMR to a 3-week generation MVP is ambitious. OMR is the
> **last milestone and the first to trim** if generation/RAG/UX need more time — the
> generate→print flow still stands alone as a strong demo without it.

## Explicitly deferred (documented, not built now)
Cloud backend, sync, analytics, multi-subject/class, accounts. See
[`08-deferred-omr-backend.md`](08-deferred-omr-backend.md).

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Model too heavy for 2 GB devices | Med | Model spike Week 1; fall back to Llama 3.2 1B / stronger quant. |
| OCR errors from watermark | Med | Cleanup pass + per-chapter spot-checks; fix worst chapters by hand. |
| Small model output quality | Med | Strong RAG grounding + schema + prompt iteration; blind review. |
| VLM captioning slower than expected | Low | It's build-time, off-device; can batch overnight; caption only key figures first. |
| SLO list unavailable | Low | Derive SLOs from chapter objectives + Key Points. |
| OMR photo accuracy (~90%) | Med | We control the sheet: fiducials + QR + capture guide + low-confidence flagging. |
| Too much for 3 weeks (gen + PDF + OMR + UI) | Med | Strict milestone order; OMR is the trimmable stretch — generate→print demo stands alone. |
