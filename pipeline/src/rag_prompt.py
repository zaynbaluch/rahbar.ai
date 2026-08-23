"""Off-device RAG prompt assembler.

Retrieves the most relevant curriculum chunks for a topic from curriculum.db and
fills a prompt template (lesson plan or MCQ) — so we can validate retrieval +
grounded-prompt quality NOW, before the model runs on-device. The Flutter app
will do the same assembly (query-embed → retrieve → fill template) on-device.

Run: uv run python -m src.rag_prompt lesson "the human digestive system"
     uv run python -m src.rag_prompt mcq "states of matter"
"""

from __future__ import annotations

import pathlib
import re
import sqlite3
import sys

import numpy as np

from .build_db import DB, embed_texts, unpack

REPO = pathlib.Path(__file__).resolve().parents[2]
TEMPLATES = {
    "lesson": REPO / "prompts" / "lesson_plan.md",
    "mcq": REPO / "prompts" / "mcq.md",
}
# Exercise blocks are question lists, not explanatory facts — exclude from the
# grounding context (see docs/06-rag-quality-plan.md, block_type metadata).
EXCLUDE_TYPES = {"exercise"}
# Safety net: some exercise sections are mislabeled "content" because OCR dropped
# spaces (e.g. "Selectthe correct option"). Match exercise-y titles tolerant of
# missing spaces so they don't pollute grounding/SLOs.
EXERCISE_TITLE = re.compile(
    r"encircle|select\s*the|give\s*answer|write\s*short|construct(ed)?\s*response|"
    r"answer\s*the\s*following|briefly\s*describe|fill\s*in|differentiate|"
    r"investigate|project|tick\b|match\s*the",
    re.I,
)


def _is_exercise(block_type: str, title: str) -> bool:
    return block_type in EXCLUDE_TYPES or bool(EXERCISE_TITLE.search(title or ""))


def retrieve(query: str, k: int = 6) -> list[tuple]:
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT id, chapter, section_no, title, block_type, page_start, "
        "page_end, text, embedding FROM chunks"
    ).fetchall()
    con.close()
    qv = embed_texts([query])[0]
    scored = []
    for r in rows:
        if _is_exercise(r[4], r[3]):
            continue
        sim = float(np.dot(qv, unpack(r[8])))
        scored.append((sim, *r[:8]))  # (sim,id,chapter,section,title,type,p_start,p_end,text)
    scored.sort(reverse=True)
    return scored[:k]


def build_context(hits: list[tuple]) -> str:
    blocks = []
    for i, h in enumerate(hits, 1):
        _, _cid, chapter, _sec, title, _bt, p0, p1, text = h
        pages = f"p{p0}" if p0 == p1 else f"p{p0}-{p1}"
        blocks.append(f"[Excerpt {i} — Ch {chapter}, {title} ({pages})]\n{text.strip()}")
    return "\n\n".join(blocks)


def derive_slos(hits: list[tuple]) -> str:
    """Rough SLO list = the distinct section titles retrieved (v1)."""
    seen, out = set(), []
    for h in hits:
        title = h[4].strip()
        if title and title not in seen:
            seen.add(title)
            out.append(title)
    return "; ".join(out[:4])


def assemble(kind: str, topic: str, k: int = 6) -> str:
    template = TEMPLATES[kind].read_text(encoding="utf-8")
    hits = retrieve(topic, k=k)
    filled = (
        template.replace("{{topic}}", topic)
        .replace("{{slos}}", derive_slos(hits))
        .replace("{{context}}", build_context(hits))
    )
    # Report retrieval quality alongside the prompt.
    header = "\n".join(
        f"  {h[0]:.3f}  [Ch{h[2]} {h[5]}] {h[4][:55]}" for h in hits
    )
    return f"# Retrieved for {topic!r}:\n{header}\n\n{'='*70}\n{filled}"


def main(argv: list[str]) -> None:
    if len(argv) < 2 or argv[0] not in TEMPLATES:
        print("usage: python -m src.rag_prompt <lesson|mcq> \"<topic>\"")
        return
    print(assemble(argv[0], " ".join(argv[1:])))


if __name__ == "__main__":
    main(sys.argv[1:])
