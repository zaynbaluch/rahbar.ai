# ADR-004 — RAG stack: EmbeddingGemma + sqlite-vec, corpus prebuilt & bundled

**Status:** Accepted · **Date:** 2026-07-04 · **Revisit flagged:** 2026-07-05

> **Update (2026-07-05):** While wiring the generation spike we found `flutter_gemma` now
> ships its **own** on-device RAG stack — **EmbeddingGemma embeddings** (`flutter_gemma_embeddings`)
> plus a vector store (`flutter_gemma_rag_qdrant` = qdrant-edge, or `flutter_gemma_rag_sqlite`).
> This could replace our hand-rolled `sqlite-vec` wiring and give us EmbeddingGemma query
> embedding in the same runtime as generation. **Caveat:** those embeddings run via LiteRT FFI
> = **arm64-only** (won't run on the x86_64 emulator), and we still prefer to **prebuild the
> corpus off-device** (Docling + captioning + embeddings) regardless. Decision to adopt
> `flutter_gemma_rag_sqlite` vs. raw `sqlite-vec` is **deferred to the RAG milestone on real
> hardware**; the "prebuilt, bundled corpus" principle below is unchanged either way.

> **Build-stage decisions (2026-07-05, implemented in `pipeline/src/build_db.py`):**
> - **Embedder = `bge-small-en-v1.5`** (ungated, 384-dim, English) via **fastembed/ONNX**
>   (no torch) — chosen over gated EmbeddingGemma to avoid HF-token/license friction. The
>   on-device query embedder (arm64, later) must match this model.
> - **Vector store = plain SQLite + brute-force cosine**, NOT the sqlite-vec extension. At
>   134 chunks × 384-dim, brute-force is instant and needs no native extension on-device —
>   simplest robust path. Embeddings stored as float32 BLOBs in a `chunks` table; the built
>   `curriculum.db` (~520 KB) is bundled at `app/assets/rag/curriculum.db`.
> - **Retrieval validated off-device**: sample science queries return the correct
>   chapter/section at 0.76–0.85 cosine. `block_type` metadata lets generation prefer
>   `content` over `exercise` chunks.
> - On-device query embedding + wiring remains for the arm64-device phase.

## Context

Generation must be **grounded in the Class 6 General Science curriculum** to stay
SNC-compliant and hallucination-free. The corpus is tiny and fixed — **one 153-page
textbook** — which is a gift: retrieval is easy, and quality comes from good chunking and
metadata, not scale. We need an on-device embedder and a vector store that coexist with the
app's SQLite store on a 2–4 GB phone.

## Decisions

### Embedding model — EmbeddingGemma (308M), 256-dim

- Best-in-class **on-device** embedder: QAT keeps RAM **<200 MB**, inference is **<15 ms**,
  and it's the top open multilingual embedder **under 500M on MTEB**.
- **Matryoshka Representation Learning** lets us truncate 768→**256 dims**, shrinking the
  shipped vector DB and speeding search with negligible quality loss.
- Pairs naturally with a Gemma generation model and is already reachable through
  flutter_gemma's embedding support — **one runtime for embed + generate**.
- Alternatives (fine, English-only): `bge-small-en-v1.5`, `gte-small`.

### Vector store — sqlite-vec

- Keeps vectors in the **same SQLite** we already use for the offline app store — one file,
  one dependency, no separate vector DB process.
- At single-textbook scale, search is trivially fast; we could even brute-force cosine, but
  `sqlite-vec` keeps it clean and future-proof.
- Alternatives: ObjectBox vector search (Flutter-native) or Isar; reconsider only if we
  outgrow SQLite.

### Corpus is prebuilt off-device and bundled

- All parsing, captioning, chunking, and embedding happen at **build time on a laptop**
  (see [ADR-005](ADR-005-pdf-preprocessing.md)). The app ships a ready `curriculum.db` in
  `app/assets/rag/`.
- **On-device, we only run one query embedding + a similarity search.** This is the crux of
  making high-quality RAG viable on cheap phones.

## Consequences

- Curriculum updates = rebuild and ship a new `curriculum.db` asset (later, downloadable).
- Chunk schema carries rich metadata (chapter, topic, SLO id, page, block-type) so we can
  filter/boost retrieval by SLO or by block type (e.g. prefer "Activity" blocks when
  building the lesson's Explore phase).
- Embedding dim (256) is fixed at build time; query embeddings must match.

## Sources

- EmbeddingGemma overview: <https://ai.google.dev/gemma/docs/embeddinggemma> · <https://developers.googleblog.com/en/introducing-embeddinggemma/> · <https://huggingface.co/blog/embeddinggemma>
- On-device RAG for app developers: <https://medium.com/google-developer-experts/on-device-rag-for-app-developers-embeddings-vector-search-and-beyond-47127e954c24>
- sqlite-vec for local RAG: <https://dev.to/aairom/embedded-intelligence-how-sqlite-vec-delivers-fast-local-vector-search-for-ai-3dpb> · <https://blog.sqlite.ai/building-a-rag-on-sqlite>
- Mobile RAG / local vector DBs 2026: <https://dev.to/devin-rosario/rag-on-mobile-local-vector-dbs-and-smart-search-2026-1ad7>
