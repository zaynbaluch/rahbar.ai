# 00 — Project Overview

## The problem

Rural Punjab schools under programs like PSRP are severely understaffed. A single teacher
often manages **60–70 students across multiple grades** and spends **up to ~12 hours a
week** manually drafting lessons and grading. **4G connectivity is unstable or absent**,
so cloud-based EdTech is unusable, and most existing platforms target *students* rather
than the *teacher burnout* that drives the rural–urban quality gap.

## The solution

**Rahbar AI** turns generative AI from an "urban luxury" into a **resilient offline
utility for teachers**. On a mid-range/budget Android phone, with no live internet, it:

1. **Generates lesson plans** — full, structured, pedagogy-rich (5E model), grounded in the
   official curriculum.
2. **Generates MCQ tests** — curriculum-aligned, with answer keys.
3. *(Later phase)* **Grades MCQ sheets** — photograph a completed bubble sheet, score it
   instantly on-device.
4. **Syncs when possible** — queued, conflict-safe writes to a cloud backend when a stable
   connection appears; aggregate data later powers school/board analytics.

Target impact: cut a rural teacher's weekly prep workload by roughly **40%**.

## MVP scope (this 3-week phase)

| In scope | Out of scope (documented for later) |
|---|---|
| General Science, **Class 6 only** | Other subjects / classes |
| **On-device generation** (lesson plans + MCQs) + RAG | Cloud backend, sync, analytics |
| **PDF export** (lesson plan, test, OMR sheet, answer key) | Multi-user / school accounts |
| **OMR camera grading** of app-generated tests (no SLM, by test ID) | iOS |
| Offline, single-device · Android-only | |
| Beautiful, intuitive UI for generate → review → print → grade | |

Rationale: the on-device SLM+RAG generation is the **riskiest, most novel** piece and is
proven first. OMR grading is added to the demo because it's **self-contained and cheap** —
it reads bubbles and looks up the stored answer key by test ID, never invoking the SLM. See
[ADR-007](decisions/ADR-007-assessment-and-omr.md). Backend/sync/analytics remain deferred.

## Goals for the build

- **State-of-the-art, genuinely impressive** within 3 weeks of full-time work.
- **Truly offline** — generation must work in airplane mode on a 2–4 GB RAM device.
- **Grounded, not hallucinated** — every generated fact traceable to the curriculum.
- **Pedagogically credible** — lesson plans a real teacher would respect and use.

## Non-goals (for now)

- Running the largest possible model. We optimize for *quality-per-byte* on cheap phones.
- Cross-platform. Rural teachers use Android; iOS/desktop add cost with no user benefit.
- Cloud inference of any kind in the core loop. The whole premise is offline-first.

## Glossary

| Term | Meaning |
|---|---|
| **SLM** | Small Language Model — a compact LLM (≈0.5–4B params) that can run on a phone. |
| **RAG** | Retrieval-Augmented Generation — grounding model output in retrieved source text to reduce hallucination. |
| **SNC** | Single National Curriculum (Pakistan). |
| **SLO** | Student Learning Outcome — a specific curriculum objective; our chunking/anchoring unit. |
| **PCTB** | Punjab Curriculum and Textbook Board — publisher of the source textbook. |
| **OMR** | Optical Mark Recognition — reading marked bubbles on an answer sheet. |
| **LiteRT** | Google's on-device runtime (formerly TensorFlow Lite); backend for flutter_gemma. |
| **GGUF** | Quantized model file format used by llama.cpp. |
| **5E** | Engage–Explore–Explain–Elaborate–Evaluate, an inquiry-based science lesson model. |
| **Quantization** | Compressing model weights (e.g. to 4-bit) to shrink RAM/footprint for on-device use. |

## Team

- **Muhammad Zain Abbas** — Technical
- **Moiz Alam** — Business

Prepared for **Contour Software** (Contour Launchpad).
