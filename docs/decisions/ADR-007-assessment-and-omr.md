# ADR-007 — MCQ tests, PDF export & OMR grading (no-SLM grading loop)

**Status:** Accepted · **Date:** 2026-07-04

> **✅ GENERATION + PDF SIDE IMPLEMENTED (2026-07-07).** The generate→structure→print
> half of the loop is built and verified (grading half still deferred):
> - `app/lib/features/generation/mcq_parser.dart` — parses the model's strict MCQ text
>   into a structured `McqTest` + answer key. Tolerant of small format drift; unit-tested
>   against **real Qwen3 1.7B output** (`test/mcq_parser_test.dart`, 3 tests).
> - `app/lib/features/export/pdf_export.dart` — renders the test to a 3-part PDF: **test
>   paper**, **OMR answer sheet** (A–D bubbles + 4 corner **fiducial markers** for the future
>   camera grader), and a teacher **answer key**. Each carries a **Test ID** (`GS6-XXXX`,
>   derived from the topic) so a scanned sheet maps back to its key with no SLM. Layout
>   visually verified by rasterizing the PDF.
> - Wired into `GenerationScreen`: structured question cards, show/hide key, and an
>   **Export/print** action via the `printing` plugin.
> Still deferred: the on-device **OMR reader/grader** (OpenCV camera pipeline) that consumes
> the fiducials + bubbles and scores against the stored key.

## Context

MCQ tests are now a first-class MVP feature with a full loop: **generate → print (PDF) →
students mark → photograph → grade on-device**. The user's requirements:

- **10 questions per test**, **mixed difficulty**.
- **Printable** (PDF) and **OMR-compatible** answer sheet.
- Grading must **read the OMR marks and score by looking up the answer key via the test
  ID — without invoking the SLM.** (Generation uses the SLM; grading never does.)

This makes grading cheap, instant, and deterministic, and keeps the demo's "OMR checking"
wow-factor fully offline.

## Decision

### MCQ test spec
- **10 questions**, 4 options each (A–D), exactly one defensibly-correct answer.
- **Mixed difficulty**, defaulting to a Bloom-laddered spread (tweakable):
  ~4 Easy (Remember/Understand), ~4 Medium (Understand/Apply), ~2 Hard (Apply/Analyze).
- Each item grounded in a retrieved curriculum chunk; distractors plausible but clearly
  wrong per the source. Each item tagged with `difficulty`, `bloom_level`, `slo_id`, `page`.

### Test identity & storage (enables no-SLM grading)
- Every generated test gets a unique **`test_id`**.
- Stored locally: `mcq_sets(test_id, topic, slo_ids, items_json, answer_key_json, created_at)`.
- Grading = read marked bubbles → **fetch `answer_key_json` by `test_id`** → compare. The
  SLM is not in this path at all.

### PDF export
- On-device, offline PDF generation (Flutter `pdf` + `printing` packages) for:
  1. the **lesson plan**, 2. the **student MCQ paper**, 3. the **OMR answer sheet**,
  4. a **teacher answer key** copy.
- Shareable / printable directly from the phone.

### OMR answer sheet design (we control the sheet, so we design for accuracy)
- Corner **fiducial/registration markers** for robust perspective correction.
- **`test_id` encoded as a QR code** (robust) + printed human-readable id.
- 10 rows × 4 bubbles, generous spacing, high-contrast; optional student name/roll region.
- Designed to push mobile-photo OMR from the typical ~90% toward scan-quality reliability.

### OMR grading flow (on-device, no SLM)
1. Capture photo (on-screen align-to-frame guide + lighting hint).
2. Detect fiducials → perspective-warp to a canonical sheet.
3. Decode QR → `test_id` → fetch `answer_key_json` from local SQLite.
4. Threshold each bubble → determine marked option per question.
5. Compare to key → score + per-question correctness.
6. **Confidence handling:** blank / multiple / faint marks flagged for quick teacher
   confirmation rather than silently guessed.
7. Save result (`grading_results`), ready to sync later for analytics.

## Consequences

- **Scope:** OMR grading moves **into the MVP** (was deferred). Backend/sync/analytics stay
  deferred; grading results are stored locally now, synced later.
- **Stack:** OpenCV via `opencv_dart`/FFI for the vision pipeline; a QR decode lib; `pdf`/
  `printing` for export — all on-device, offline.
- **Data model:** add `answer_key_json` + `test_id` to `mcq_sets`, and a `grading_results`
  table (see [`../01-architecture.md`](../01-architecture.md)).
- **Timeline:** this is the most ambitious addition for 3 weeks; treat OMR as the **last
  milestone** and the first candidate to trim if generation/RAG/UX need more time
  (see [`../07-3week-plan.md`](../07-3week-plan.md)).

## Sources

- Mobile OMR accuracy & pipelines: <https://pyimagesearch.com/2016/10/03/bubble-sheet-multiple-choice-scanner-and-test-grader-using-omr-python-and-opencv/> · <https://stacks.stanford.edu/file/druid:yt916dh6570/Moon_Chidrewar_Yang_Mobile_OMR_System.pdf>
- OMR tooling references: <https://github.com/Udayraj123/OMRChecker> · <https://github.com/iansan5653/open-mcr>
