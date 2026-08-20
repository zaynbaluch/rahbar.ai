"""Stage 4 — embed chunks + build the bundled vector DB.

Embeds each curriculum chunk with **bge-small-en-v1.5** (ungated, 384-dim,
English) via fastembed (ONNX, no torch) and writes a self-contained SQLite
`curriculum.db`. The corpus is tiny (~134 chunks) so we store embeddings as
BLOBs and do brute-force cosine on-device — no sqlite-vec extension needed
(see docs/decisions/ADR-004).

Run: uv run python -m src.build_db          # build DB
     uv run python -m src.build_db "how do plants reproduce"   # + retrieval test
"""

from __future__ import annotations

import json
import pathlib
import sqlite3
import struct
import sys

import numpy as np
from fastembed import TextEmbedding

REPO = pathlib.Path(__file__).resolve().parents[2]
# Prefer the paragraph-level chunks (chunk_fine.py) — denser retrieval, smaller
# RAG prefill — falling back to section chunks if the fine pass hasn't been run.
_FINE = REPO / "data" / "processed" / "chunks_fine.jsonl"
CHUNKS = _FINE if _FINE.exists() else REPO / "data" / "processed" / "chunks.jsonl"
DB = REPO / "app" / "assets" / "rag" / "curriculum.db"
MODEL = "BAAI/bge-small-en-v1.5"
DIM = 384


def pack(vec: np.ndarray) -> bytes:
    return struct.pack(f"{len(vec)}f", *vec.astype(np.float32))


def unpack(blob: bytes) -> np.ndarray:
    return np.array(struct.unpack(f"{len(blob) // 4}f", blob), dtype=np.float32)


def embed_texts(texts: list[str]) -> np.ndarray:
    model = TextEmbedding(model_name=MODEL)
    vecs = np.array(list(model.embed(texts)), dtype=np.float32)
    # L2-normalize so dot product == cosine similarity.
    vecs /= np.linalg.norm(vecs, axis=1, keepdims=True)
    return vecs


def build() -> list[dict]:
    chunks = [json.loads(l) for l in open(CHUNKS, encoding="utf-8")]
    print(f"Embedding {len(chunks)} chunks with {MODEL} …")
    vecs = embed_texts([c["text"] for c in chunks])

    DB.parent.mkdir(parents=True, exist_ok=True)
    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)
    con.execute("""
        CREATE TABLE chunks (
            id TEXT PRIMARY KEY,
            chapter INTEGER,
            section_no TEXT,
            title TEXT,
            block_type TEXT,
            page_start INTEGER,
            page_end INTEGER,
            figure_pages TEXT,
            text TEXT,
            embedding BLOB
        )""")
    con.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    con.executemany(
        "INSERT INTO chunks VALUES (?,?,?,?,?,?,?,?,?,?)",
        [
            (
                c["id"], c.get("chapter"), c.get("section_no"), c.get("title"),
                c.get("block_type"), c.get("page_start"), c.get("page_end"),
                json.dumps(c.get("figure_pages", [])), c["text"], pack(vecs[i]),
            )
            for i, c in enumerate(chunks)
        ],
    )
    con.executemany(
        "INSERT INTO meta VALUES (?,?)",
        [("embed_model", MODEL), ("dim", str(DIM)), ("n_chunks", str(len(chunks)))],
    )
    con.commit()
    con.close()
    print(f"Wrote {DB} ({DB.stat().st_size // 1024} KB, {len(chunks)} chunks)")
    return chunks


def retrieval_test(query: str, k: int = 4) -> None:
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT id, chapter, section_no, title, block_type, embedding FROM chunks"
    ).fetchall()
    con.close()
    qv = embed_texts([query])[0]
    scored = []
    for cid, ch, sec, title, bt, blob in rows:
        sim = float(np.dot(qv, unpack(blob)))
        scored.append((sim, cid, ch, sec, title, bt))
    scored.sort(reverse=True)
    print(f"\nTop {k} for: {query!r}")
    for sim, cid, ch, sec, title, bt in scored[:k]:
        print(f"  {sim:.3f}  [{cid} ch{ch} {bt}] {title[:60]}")


def main(argv: list[str]) -> None:
    build()
    if argv:
        retrieval_test(" ".join(argv))


if __name__ == "__main__":
    main(sys.argv[1:])
