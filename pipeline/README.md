# pipeline/ — build-time work (Python, off-device)

Two pipelines run on the laptop, never on the phone.

## 1. Curriculum ingestion → `curriculum.db`

watermark cleanup → Docling OCR → block typing → SLO-aligned chunking → **bge-small**
(384-dim) → SQLite `app/assets/rag/curriculum.db` (brute-force cosine; no sqlite-vec).

See [ADR-005](../docs/decisions/ADR-005-pdf-preprocessing.md), [ADR-004](../docs/decisions/ADR-004-rag-stack.md).

```
uv run python -m src.preprocess     # 1  watermark removal (flat-field)
uv run python -m src.parse          # 2  Docling + Tesseract (batched, resumable)
uv run python -m src.chunk          # 3  block typing + section chunks
uv run python -m src.chunk_fine     # 3b paragraph sub-chunks
uv run python -m src.build_db       # 4  embed → curriculum.db
```

## 2. Content generation → `content_pack.db`

The MCQ bank + 5E section library the app ships and serves **instantly**. Generating on the
phone cost ~3.5 min per test and left answer keys unverifiable — see
[ADR-008](../docs/decisions/ADR-008-build-time-content.md).

```
bash ../scripts/setup-genserver.sh --build    # llama.cpp + CUDA, fetch Qwen3-8B  (once)
bash ../scripts/setup-genserver.sh --serve    # leave running in its own terminal

uv run python -m src.topics                   # the 88-topic catalogue (from curriculum.db)
uv run python -m src.gen_content              # generate + verify   (hours; resumable)
uv run python -m src.build_content_db         # pack + review.html  (idempotent)
```

`gen_content` runs five stages per topic — `topic_meta`, `mcq_gen`, `mcq_verify`, `plan_gen`,
`plan_verify` — and **checkpoints each one**, so a laptop that sleeps, crashes or runs out of
power loses nothing. Re-running the same command resumes; it only does the missing work.

```
uv run python -m src.gen_content --dry-run              # what's left to do
uv run python -m src.gen_content --only ch04-4_1-e09b   # one topic (do this first!)
uv run python -m src.gen_content --stage mcq_gen --force
RAHBAR_N_CANDIDATES=20 uv run python -m src.gen_content # smaller bank, faster run
```

**Read `data/processed/content/review.html` before shipping a pack.** Items the verifier
marked `unsure` are held back from the pack and listed there for a human to judge; a wrong
answer key reaches students through the OMR grader with nobody in between
([ADR-007](../docs/decisions/ADR-007-assessment-and-omr.md)).
