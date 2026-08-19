# ADR-005 — PDF preprocessing: watermark cleanup → Docling OCR → VLM captioning → SLO chunking

**Status:** Accepted · **Date:** 2026-07-04

## Context

The source is the **PCTB "Web Version" Class 6 General Science** textbook — a **153-page
scanned/image-only PDF** (printed via Foxit PhantomPDF; no embedded text or fonts). Naive
extraction (`pdftotext`) yields **nothing**. Inspection findings:

- Text is **crisp printed English** (not handwriting) → OCR accuracy will be high.
- A **diagonal grey "Web Version of PCTB Textbook / Not for Sale" watermark** crosses body
  text and tables → must be mitigated before OCR.
- The book is **already pedagogically structured**: numbered sections, labelled **figures**
  (organ systems, cells, circuits), **"Inquiry"** discussion boxes, **"Activity/Assessment"**
  boxes (some with tables), and **"Key Points"** summaries.

The structure is an asset: those typed blocks map directly onto lesson-plan sections and let
the generator retrieve the book's *own* inquiries/activities instead of inventing them.

## Pipeline (build-time, off-device)

1. **Watermark mitigation** — the watermark is light grey; use thresholding / channel
   separation / inpainting (OpenCV/PIL) to suppress it before OCR, per page. Spot-check that
   body text is preserved.
2. **OCR + layout parse — Docling** (Surya/Tesseract engines). Docling preserves semantic
   hierarchy and tables and outputs structured Markdown / `DoclingDocument`. Chosen over
   Marker (faster but less structure-rich) because textbook structure is central to quality.
   MinerU/PyMuPDF4LLM considered; Docling wins for structured RAG.
3. **Block typing** — tag each parsed block as `section | inquiry | activity | key_points |
   figure_caption | table`. These types drive retrieval and lesson-plan assembly.
4. **Diagram captioning (VLM)** — extract each figure and generate a text description
   (e.g. "labelled diagram of the human digestive system: mouth, oesophagus, stomach, small
   intestine, large intestine, rectum"), indexed alongside the printed caption. Science
   diagrams carry exam-relevant content that pure OCR drops.
5. **SLO-aligned chunking** — chunk by SNC Student Learning Outcome / sub-topic (not blind
   fixed windows), attaching metadata: `chapter, topic, slo_id, page, block_type`. **This is
   the single biggest quality lever** and is easy at single-textbook scale.
6. **Embed + build DB** — EmbeddingGemma (256-dim) → `sqlite-vec` → `curriculum.db`.

## Decision

Adopt the pipeline above with **Docling as the parser** and a **VLM captioning step** for
figures. Preserve the book's native pedagogical blocks as typed chunks. All of this runs at
build time; only the resulting `curriculum.db` ships.

## Consequences

- Requires a one-time curation pass with **per-chapter OCR spot-checks** (watermark makes
  this non-optional) — budgeted in Week 1.
- We need an SLO source for Class 6 General Science to anchor chunks; if an official SLO list
  isn't readily digital, we derive SLOs from chapter objectives + Key Points (tracked in
  [`../09-open-questions.md`](../09-open-questions.md)).
- VLM captioning is an offline, laptop/GPU or API step — it does **not** run on-device.
- Output intermediates land in `data/processed/` for inspection and re-runs.

## Sources

- Best PDF parsers for RAG 2026: <https://www.firecrawl.dev/blog/best-pdf-parsers> · <https://blazedocs.io/blog/best-pdf-parser-for-rag>
- Docling for local RAG (tables/structure): <https://towardsdatascience.com/parse-pdfs-for-rag-locally-with-docling-rich-tables-no-cloud-upload/> · <https://www.marktechpost.com/2026/06/16/how-to-build-a-parsing-pipeline-with-docling-parse-for-layout-aware-document-intelligence/>
- Docling vs Marker: <https://docs.bswen.com/blog/2026-04-16-docling-vs-marker-document-parsing/>
- Open-source PDF→Markdown tools: <https://themenonlab.blog/blog/best-open-source-pdf-to-markdown-tools-2026>
