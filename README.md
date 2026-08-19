# Rahbar AI

**Edge-AI teaching assistant for understaffed low-cost schools in Punjab.**

Rahbar AI is an **offline-first Android app** that helps a single teacher managing 60–70
students across multiple grades. It runs a **small language model on the phone** to
generate SNC-compliant, pedagogically-rich **lesson plans** and **MCQ tests**, grounded in
the official curriculum via on-device **RAG**, and (in a later phase) grades MCQ answer
sheets from the phone camera. It works with **no internet** and syncs only when a stable
connection is available.

> Status: **Research & technology-decision phase.** This repo currently holds the decision
> records and research that will drive the build. See [`docs/`](docs/).

## MVP scope (first 3 weeks)

- **One subject, one class:** General Science, Class 6 (PCTB textbook).
- **Core loop:** on-device generation (lesson plans + 10-MCQ tests) with RAG → **PDF export**
  → **OMR camera grading** of the printed test (scored by test ID, no SLM).
- Deferred to later phases: cloud backend, sync, analytics, multi-subject/class.

## Repository layout

| Path | Purpose |
|---|---|
| `docs/` | Decision records (ADRs), architecture, pedagogy & tooling research. **Start here.** |
| `app/` | Flutter app (Android-only). Runtime: on-device SLM + query embedding + retrieval + UI. |
| `pipeline/` | Off-device, build-time Python: watermark→OCR→parse→caption→chunk→embed→build vector DB. |
| `prompts/` | Versioned lesson-plan & MCQ prompt templates. |
| `eval/` | Groundedness + output-quality evaluation harness. |
| `data/raw/` | Source PDFs (textbook, proposal). Git-ignored. |
| `data/processed/` | Intermediate parsed markdown / chunks / vectors. |

## Key decisions at a glance

- **App:** Flutter (Android-only) — best memory/perf balance at 2–4 GB RAM with a first-class on-device LLM path.
- **Inference:** flutter_gemma (LiteRT); candidate models Gemma 3n E2B / Qwen3 1.7B / Llama 3.2 1–3B (chosen by on-device spike).
- **RAG:** EmbeddingGemma + `sqlite-vec`, corpus prebuilt off-device and bundled in the app.
- **Preprocessing:** Docling (layout-aware OCR) + VLM diagram captioning + SLO-aligned chunking.
- **Lesson plans:** 5E model spine + Bloom-tagged objectives, retrieval starter, Socratic questions, low-cost activities, exit-ticket assessment; one **50-min** period per topic.
- **Assessment:** 10-question mixed-difficulty MCQ tests, PDF/printable, **OMR-gradable by test ID without invoking the SLM**.

Full rationale in [`docs/decisions/`](docs/decisions/).
