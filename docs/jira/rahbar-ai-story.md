# Jira Story — Rahbar AI

A ready-to-enter Jira **Story** with **Sub-tasks** grouped into three weekly
milestones. Copy the fields into Jira manually, or bulk-import
[`rahbar-ai-import.csv`](rahbar-ai-import.csv) (instructions at the bottom).

---

## 📘 STORY

**Summary:** Rahbar AI — Offline-first Edge-AI Teaching Assistant (Class 6 General Science MVP)

**Issue type:** Story · **Priority:** High · **Labels:** `rahbar-ai` `edge-ai` `mvp` `android`
**Estimate:** 69 story points across 3 weekly milestones

### Description

Rural Punjab schools are severely understaffed — one teacher often manages 60–70
students across grades and spends up to ~12 hours/week manually drafting lessons
and grading. Unstable/absent connectivity makes cloud EdTech unusable.

**Rahbar AI** is an **offline-first Android app** that runs a small language model
**on the teacher's phone** to generate SNC-compliant, pedagogy-rich **lesson plans**
and **MCQ tests**, grounded in the official curriculum via on-device **RAG**, and
**grades MCQ answer sheets by camera** — all with no internet, syncing later.

**MVP scope:** one subject, one class — **General Science, Class 6** (PCTB textbook).

**Tech direction:** Flutter (Android-only) · on-device SLM via flutter_gemma/LiteRT ·
RAG (embeddings + on-device vector search over the curriculum) · OpenCV OMR grading ·
local SQLite; cloud backend/sync deferred post-MVP.

### Acceptance criteria

- [ ] Generates a full, structured **lesson plan** (5E model) for a Class 6 General
      Science topic, **fully offline** on a budget Android device.
- [ ] Generates a **10-question, mixed-difficulty MCQ test** with an answer key.
- [ ] All generated content is **grounded in the curriculum** (no hallucinated facts;
      traceable to textbook chunks).
- [ ] **Exports to PDF** (lesson plan, student paper, OMR answer sheet, teacher key).
- [ ] **Grades a photographed MCQ sheet** on-device by test ID — without invoking the SLM.
- [ ] Runs on a **2–4 GB RAM** Android device with usable latency; polished, demoable UI.

### Out of scope (post-MVP)

Cloud backend, multi-device sync, aggregate analytics, other subjects/classes, iOS,
multi-user/school accounts.

---

## 🗓️ Milestone 1 — Foundation & De-risking (Week 1)

Prove the two hardest pieces early: on-device generation and the curriculum pipeline.
**Label:** `m1-foundation`

| # | Sub-task | Area | Pts |
|---|---|---|---|
| 1 | **Set up Flutter (Android) project + dev toolchain + budget-device emulator** — Flutter/Android SDK, project scaffold, an emulator profile approximating a 2–4 GB RAM phone. | `flutter` | 3 |
| 2 | **Integrate on-device inference engine** — wire flutter_gemma (MediaPipe/LiteRT), load & run a quantized model, stream tokens. | `on-device-ml` | 5 |
| 3 | **Model spike & selection** — benchmark candidate SLMs (Gemma 3n E2B / Qwen / Llama 3.2) for RAM, latency, and output quality on target hardware; pick one. | `on-device-ml` | 5 |
| 4 | **Curriculum OCR + layout parse** — run layout-aware OCR (Docling + Tesseract) over the scanned Class 6 textbook; handle the watermark. | `rag` | 5 |
| 5 | **Section/SLO-aligned chunking + block typing** — segment into topic chunks with metadata (chapter, section, page, block type: content/activity/key-points/exercise). | `rag` | 3 |
| 6 | **Embed chunks + build bundled vector DB** — embed with a compact English model, build a small on-device vector store shipped as an app asset. | `rag` | 3 |

**Milestone total: 24 pts**

---

## 🗓️ Milestone 2 — Grounded Generation & Assessment Content (Week 2)

Turn the model + corpus into grounded, structured lesson plans and MCQ tests.
**Label:** `m2-generation`

| # | Sub-task | Area | Pts |
|---|---|---|---|
| 7 | **On-device retrieval wiring** — embed the query, run vector similarity search, return top-k curriculum chunks (metadata-aware: prefer content over exercises). | `rag` | 3 |
| 8 | **Grounded prompt templates** — anti-hallucination prompting, structured (JSON) output, "answer only from provided excerpts / say if unknown". | `on-device-ml` | 3 |
| 9 | **Lesson-plan generation (5E schema)** — objectives (Bloom-tagged), revision starter, Socratic questions, low-cost activity, delivery, exit-ticket; 50-min period with split suggestion. | `on-device-ml` | 5 |
| 10 | **MCQ test generation** — 10 questions, mixed difficulty, one correct + plausible distractors, answer key, unique test ID. | `on-device-ml` | 3 |
| 11 | **PDF export** — print-ready lesson plan, student MCQ paper, OMR answer sheet (fiducial markers + QR test ID), and teacher answer key. | `flutter` | 5 |
| 12 | **RAG quality eval harness** — groundedness check, curriculum-fit, MCQ validity, retrieval hit-rate on a golden set. | `rag` | 3 |

**Milestone total: 22 pts**

---

## 🗓️ Milestone 3 — OMR Grading, UX & Demo (Week 3)

Close the loop (print → grade), polish the experience, and prepare the demo.
**Label:** `m3-demo`

| # | Sub-task | Area | Pts |
|---|---|---|---|
| 13 | **OMR camera grading (no SLM)** — capture with align guide → fiducial perspective-warp → decode test ID → look up answer key → score → flag low-confidence marks. | `computer-vision` | 8 |
| 14 | **Core UI (Material 3)** — topic/SLO picker → generating state → sectioned, editable lesson plan → MCQ view → saved library. | `ux` | 5 |
| 15 | **Offline persistence** — local SQLite for generated plans, tests, answer keys, grading results, and settings. | `flutter` | 3 |
| 16 | **On-device performance tuning** — memory/latency profiling, graceful low-RAM behavior, "instant-feel" generation. | `on-device-ml` | 3 |
| 17 | **Blind quality review + fixes** — teacher-style review of generated plans/MCQs for correctness, curriculum fit, difficulty; fix issues. | `docs` | 2 |
| 18 | **Demo prep + documentation** — demo script, seed content, README/architecture write-up, walkthrough. | `docs` | 2 |

**Milestone total: 23 pts**

---

## 📥 Importing into Jira (CSV)

1. Jira → your project → **Filters/Issues → Import issues from CSV** (or **Project settings → Import**; needs project-admin rights).
2. Upload [`rahbar-ai-import.csv`](rahbar-ai-import.csv).
3. Map columns: `Issue Type`, `Summary`, `Description`, `Labels`, `Story Points`, `Priority`, and the **`Issue ID` / `Parent ID`** pair (this is what links sub-tasks to the Story).
4. Ensure your project has the **Sub-task** issue type enabled and a **Story Points** field.
5. After import: assign the sub-tasks to **Sprints 1–3** (or use the `m1/m2/m3` labels as your milestone filter), set assignees, and dates.

> Tip: the milestone labels (`m1-foundation`, `m2-generation`, `m3-demo`) let you
> filter/board by milestone even though everything hangs off a single Story.
