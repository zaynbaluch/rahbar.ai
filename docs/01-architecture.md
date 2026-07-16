# 01 — Architecture

## Guiding principle: split the work by *when* and *where* it runs

The single most important architectural idea in Rahbar AI is separating **build-time,
off-device work** from **runtime, on-device work**. Everything expensive and one-time
happens on a laptop before shipping; the phone only does what it must, at query time.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  BUILD TIME  (developer laptop / CI — runs once per curriculum update)     │
│                                                                            │
│   Textbook PDF ──► watermark cleanup ──► OCR + layout parse (Docling)      │
│        │                                        │                          │
│        │                                        ▼                          │
│   figures ──► VLM captioning ─────────►  structured Markdown + typed       │
│                                          blocks (section / inquiry /        │
│                                          activity / key-points)            │
│                                                 │                          │
│                                                 ▼                          │
│                                     SLO-aligned chunking + metadata        │
│                                                 │                          │
│                                                 ▼                          │
│                              EmbeddingGemma → vectors → build sqlite-vec DB │
│                                                 │                          │
└─────────────────────────────────────────────────┼──────────────────────────┘
                                                   ▼  (bundled as an app asset)
┌──────────────────────────────────────────────────────────────────────────┐
│  RUN TIME  (teacher's Android phone — fully offline)                        │
│                                                                            │
│   Teacher picks topic / SLO ──► build query                                │
│        │                                                                   │
│        ▼                                                                   │
│   EmbeddingGemma (on-device) embeds query ──► sqlite-vec similarity search │
│        │                                              │                    │
│        │                                              ▼                    │
│        │                                   top-k curriculum chunks          │
│        ▼                                              │                    │
│   prompt template  ◄──────────────────────────────────┘                    │
│        │                                                                   │
│        ▼                                                                   │
│   SLM (Gemma 3n E2B via flutter_gemma / LiteRT) ──► lesson plan / MCQs      │
│        │                                                                   │
│        ▼                                                                   │
│   render + let teacher edit ──► save to local SQLite ──► (later) sync queue │
└──────────────────────────────────────────────────────────────────────────┘
```

**Why this matters:** Docling parsing, VLM captioning, and embedding 153 pages are far too
heavy for a 2–4 GB phone. Doing them at build time means the phone ships with a small,
pre-computed `sqlite-vec` database and only ever runs (a) one lightweight query embedding
and (b) SLM generation. This is what makes "state-of-the-art RAG quality" feasible on cheap
hardware.

## On-device runtime components (Flutter app)

| Component | Tech | Role |
|---|---|---|
| UI | Flutter + Material 3 | Topic selection, generation, review/edit, saved library. |
| Generation | flutter_gemma (LiteRT) | Runs the quantized SLM for lesson plans + MCQs. |
| Query embedding | EmbeddingGemma (via flutter_gemma / LiteRT) | Embeds the teacher's query for retrieval. |
| Vector search | `sqlite-vec` | Similarity search over the bundled curriculum corpus. |
| PDF export | `pdf` + `printing` | Print-ready lesson plan, MCQ paper, OMR answer sheet, teacher answer key. |
| OMR grading | OpenCV (`opencv_dart`/FFI) + QR decode | Grade a photographed answer sheet **on-device, no SLM** — decode `test_id`, look up the stored key, score. |
| Local store | SQLite (`drift`) | Generated content, answer keys, grading results, edit history, settings; hosts the vector table. |
| Sync queue *(later)* | `drift` + background worker | Conflict-safe queued writes when connectivity returns. |

## Build-time pipeline components (Python, off-device)

| Stage | Tech | Output |
|---|---|---|
| Watermark cleanup | OpenCV / PIL (thresholding/inpainting) | De-watermarked page images. |
| OCR + layout parse | Docling (Surya/Tesseract) | Structured Markdown with hierarchy + tables. |
| Diagram captioning | Vision-Language Model | Text descriptions of figures. |
| Chunking | Custom (SLO-aligned) | Chunks + metadata (chapter, topic, SLO, page, block-type). |
| Embedding | EmbeddingGemma (256-dim, Matryoshka) | Vectors. |
| DB build | `sqlite-vec` | `curriculum.db` bundled into `app/assets/rag/`. |

## Data model (initial sketch, local SQLite)

- `chunks(id, text, chapter, topic, slo_id, page, block_type, embedding)` — the RAG corpus (read-only, shipped).
- `lesson_plans(id, topic, slo_ids, content_json, created_at, edited_at)` — generated + teacher-edited.
- `mcq_sets(test_id, topic, slo_ids, items_json, answer_key_json, created_at)` — generated tests; `test_id` is printed/QR-encoded on the sheet and is the grading lookup key.
- `grading_results(id, test_id, student_ref, score, per_question_json, graded_at, synced)` — OMR outcomes.
- `settings(key, value)` — model choice, language, preferences.
- *(later)* `sync_queue(id, entity, op, payload, status, attempts)` — offline write queue.

### Grading flow (on-device, no SLM)

```
photo of sheet ─► detect fiducials ─► perspective warp ─► decode QR (test_id)
      └─► fetch answer_key_json WHERE test_id ─► read bubbles ─► compare ─► score
          └─► flag blank/multiple/faint marks for teacher confirmation ─► save grading_results
```

The SLM is never invoked during grading — scoring is a deterministic key lookup. See
[ADR-007](decisions/ADR-007-assessment-and-omr.md).

## Later-phase components (documented, not built now)

- **Backend + analytics** — FastAPI + PostgreSQL, Dockerized; account/content/model-version
  distribution and aggregate weak-SLO analytics for headmasters/boards.
- **Sync** — flush local `grading_results` / content via `sync_queue` when connectivity returns.

*(OMR grading is now an MVP feature — see the grading flow above and [ADR-007](decisions/ADR-007-assessment-and-omr.md).)*

## Cross-cutting decisions

- **Everything English** (UI + generated content), matching the English-medium textbook.
- **Android-only**, indefinitely — the user base has no iOS/laptops.
- **No network in the core loop** — sync is strictly additive and out-of-band.
- **Model + corpus are versioned assets** — the app can later pull updated corpora/models,
  but always ships with a working offline set.
