# 06 — RAG Quality & Anti-Hallucination Plan

The core promise is **SNC-compliant, non-hallucinated** output. On a small on-device model,
quality is won mostly in **retrieval and prompting**, not model size. This doc defines how
we get and prove quality.

## 1. Corpus quality (build-time)

- **Clean OCR** via watermark-cleanup + Docling; **spot-check every chapter** (watermark
  makes silent OCR errors likely). See [ADR-005](decisions/ADR-005-pdf-preprocessing.md).
- **Block typing** — every chunk tagged `section | inquiry | activity | key_points |
  figure_caption | table` so retrieval can prefer the right material per lesson section.
- **VLM diagram captions** indexed so figure content is retrievable.
- **SLO-aligned chunks** with `chapter, topic, slo_id, page` metadata.

## 2. Chunking strategy

- Chunk on **semantic boundaries** (sub-topic / SLO), not fixed token windows.
- Keep chunks small enough to be precise but whole enough to be self-contained (target
  ~150–350 words; keep a table or a Key-Points list intact).
- Store the **printed caption + VLM caption together** for each figure.
- Attach a short **breadcrumb** (chapter → section) to each chunk's text so the model always
  sees where a fact came from.

## 3. Retrieval strategy

- Embed the query with **EmbeddingGemma (256-dim)**; top-k similarity via `sqlite-vec`.
- **Metadata-aware retrieval**: when assembling a lesson plan, bias/filter by block type per
  section (e.g. `activity` for Explore, `inquiry` for Engage/Socratic, `key_points` for recap)
  and by the selected topic/SLO.
- Start simple (top-k dense). Add **light re-ranking** or query expansion only if eval shows
  retrieval misses. At single-textbook scale, dense retrieval is usually enough.

## 4. Grounded prompting (anti-hallucination)

- Templates instruct: **"Use only the provided curriculum excerpts. If the excerpts don't
  cover a required part, say so — do not invent facts."**
- Provide retrieved chunks as clearly delimited context with their breadcrumbs.
- For MCQs: require each question + correct answer to be **supported by a specific excerpt**;
  distractors must be plausible but clearly wrong per the source.
- Constrain output to the **structured schema** (JSON) so sections can't drift.
- Keep generation **temperature modest** for factual sections; a touch higher only for hooks
  / activity phrasing.

## 5. Evaluation harness (`eval/`)

| Check | Method | Pass bar |
|---|---|---|
| **Groundedness** | For a sample of generated lessons/MCQs, verify each factual claim traces to a retrieved chunk against a hand-built SLO checklist. | No unsupported factual claims. |
| **Curriculum fit** | Do objectives/questions map to real Class 6 SLOs? | ≥ target coverage, no off-syllabus content. |
| **MCQ validity** | Exactly one defensibly-correct option; distractors plausible; no ambiguity. | Manual blind review. |
| **Retrieval hit-rate** | For seed questions, is the answer-bearing chunk in top-k? | High hit-rate; investigate misses. |
| **On-device viability** | Peak RAM, latency, tokens/sec on a real 2–4 GB device. | <~2 GB peak; usable latency. |

- Maintain a small **golden set** of topics/questions with expected sources for regression
  testing as we change chunking/prompts/models.
- **Blind human review** by the developer and, ideally, a practicing teacher before the demo.

## 6. Known risks & mitigations

| Risk | Mitigation |
|---|---|
| Watermark corrupts OCR | Dedicated cleanup pass + per-chapter spot-checks. |
| Small model still drifts | Strong grounding prompt + schema constraint + "say if unknown". |
| Diagram-dependent SLOs | VLM captions make diagram content retrievable. |
| Retrieval misses rephrased queries | Query expansion / light re-rank if eval flags it. |
| SLO list unavailable | Derive SLOs from chapter objectives + Key Points (see open questions). |
