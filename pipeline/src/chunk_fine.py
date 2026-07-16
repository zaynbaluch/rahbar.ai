"""Stage 3b — split big section chunks into paragraph-level sub-chunks.

The section-level chunks (chunk.py) are good for structure but bloat the RAG
prefill: retrieving 4 whole sections ≈ 5 K chars, much of it not relevant to the
query. Splitting long *content* blocks into paragraph sub-chunks lets retrieval
pull the few most relevant paragraphs → denser, more on-topic context in far
fewer tokens (faster prefill AND faster generation on-device). Non-content blocks
(exercises/activities/short defs) pass through unchanged.

Run: uv run python -m src.chunk_fine        # writes chunks_fine.jsonl
"""

from __future__ import annotations

import json
import pathlib

REPO = pathlib.Path(__file__).resolve().parents[2]
SRC = REPO / "data" / "processed" / "chunks.jsonl"
OUT = REPO / "data" / "processed" / "chunks_fine.jsonl"

# Only split content blocks longer than this; smaller ones are already tight.
SPLIT_MIN = 500
# Target sub-chunk size (chars). Paragraphs are packed up to this, never split
# mid-paragraph, so each sub-chunk stays a coherent idea.
TARGET = 450


def split_paragraphs(text: str) -> list[str]:
    """Group the section's lines into ~TARGET-char paragraph sub-chunks.

    Lines are single-'\\n'-separated (incl. short sub-headings). A short line
    (a sub-heading like 'Physical digestion') is kept attached to the paragraph
    that follows it rather than emitted alone.
    """
    lines = [ln.strip() for ln in text.split("\n") if ln.strip()]
    subs: list[str] = []
    buf: list[str] = []
    size = 0
    for ln in lines:
        buf.append(ln)
        size += len(ln) + 1
        # Flush once we've accumulated ~TARGET, but not right after a short
        # heading-like line (keep it with the next paragraph).
        if size >= TARGET and len(ln) > 40:
            subs.append(" ".join(buf))
            buf, size = [], 0
    if buf:
        subs.append(" ".join(buf))
    return subs or [text.strip()]


def main() -> None:
    chunks = [json.loads(l) for l in open(SRC, encoding="utf-8")]
    out: list[dict] = []
    split_count = 0
    for c in chunks:
        text = c.get("text", "")
        if c.get("block_type") == "content" and len(text) > SPLIT_MIN:
            parts = split_paragraphs(text)
            if len(parts) > 1:
                split_count += 1
                for i, part in enumerate(parts):
                    sub = dict(c)
                    sub["id"] = f"{c['id']}_{i}"
                    sub["text"] = part
                    out.append(sub)
                continue
        out.append(c)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        for c in out:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")

    lens = [len(c["text"]) for c in out]
    print(f"{len(chunks)} chunks -> {len(out)} fine chunks "
          f"(split {split_count} big content blocks)")
    print(f"fine chunk len: mean={sum(lens)//len(lens)} "
          f"max={max(lens)} (was up to 5731)")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
