"""Stage 3 — block typing + section/SLO-aligned chunking.

Reads the Docling batch JSONs (reading order via body-tree refs), skips front/
back matter, segments the book into **section-aligned chunks** with metadata,
and tags pedagogical blocks (objectives / inquiry / activity / key-points /
did-you-know / exercise). Emits chunks.jsonl for the embedding stage.

See docs/decisions/ADR-005 & docs/06-rag-quality-plan.md.

Run: uv run python -m src.chunk
"""

from __future__ import annotations

import glob
import json
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
BATCH_DIR = REPO / "data" / "processed" / "parse" / "batches"
OUT = REPO / "data" / "processed" / "chunks.jsonl"

# Residual watermark / footer strings to strip from OCR text.
NOISE = re.compile(
    r"(web version of pctb.*?textbook|not for sale[- ]*pesrp|not for sale)",
    re.I,
)
WS = re.compile(r"[ \t]+")

NUM_SECTION = re.compile(r"^\d+\.\d")           # 1.1, 1.3.1 ...
CHAPTER_OBJECTIVES = re.compile(r"in this chapter we will learn about", re.I)
EXERCISE = re.compile(
    r"(encircle|write short answer|select the correct|construct(ed)? response|"
    r"answer the following|differentiate|investigate|project|briefly describe|"
    r"fill in the blank|tick|match)",
    re.I,
)
BOX = [
    ("key_points", re.compile(r"^\s*key\s*points", re.I)),
    ("inquiry", re.compile(r"^\s*inquiry\b", re.I)),
    ("activity", re.compile(r"^\s*activity\b", re.I)),
    ("did_you_know", re.compile(r"^\s*do you know", re.I)),
]


def clean(text: str) -> str:
    text = NOISE.sub(" ", text)
    text = WS.sub(" ", text)
    return text.strip()


def batch_start(path: str) -> int:
    m = re.search(r"batch_p(\d+)-", path)
    return int(m.group(1)) if m else 1


def ordered_items() -> list[dict]:
    """Flatten all batches into one reading-ordered stream of items.

    Each item: {page, kind, label, level, text}. kind ∈ {text, picture, table}.
    """
    items: list[dict] = []
    for path in sorted(glob.glob(str(BATCH_DIR / "batch_*.docling.json")),
                       key=batch_start):
        d = json.load(open(path, encoding="utf-8"))
        start = batch_start(path)
        pools = {
            "texts": d.get("texts", []),
            "pictures": d.get("pictures", []),
            "tables": d.get("tables", []),
            "groups": d.get("groups", []),
        }

        def abs_page(obj) -> int:
            rel = obj["prov"][0]["page_no"] if obj.get("prov") else 1
            return start + rel - 1

        def walk(children: list[dict]) -> None:
            for child in children:
                ref = child.get("$ref")
                if not ref:
                    continue
                typ, idx = ref.lstrip("#/").split("/")
                obj = pools[typ][int(idx)]
                if typ == "groups":  # e.g. a list — recurse into its children
                    walk(obj.get("children", []))
                elif typ == "texts":
                    items.append({
                        "page": abs_page(obj), "kind": "text",
                        "label": obj.get("label"), "level": obj.get("level"),
                        "text": clean(obj.get("text", "")),
                    })
                elif typ == "pictures":
                    items.append({"page": abs_page(obj), "kind": "picture",
                                  "label": "picture", "text": ""})
                elif typ == "tables":
                    items.append({"page": abs_page(obj), "kind": "table",
                                  "label": "table", "text": ""})

        walk(d.get("body", {}).get("children", []))
    return items


def chapter_of(section_no: str) -> int | None:
    m = re.match(r"(\d+)\.", section_no)
    return int(m.group(1)) if m else None


def block_type_of(heading: str) -> str:
    for name, pat in BOX:
        if pat.search(heading):
            return name
    if CHAPTER_OBJECTIVES.search(heading):
        return "objectives"
    if NUM_SECTION.match(heading) and EXERCISE.search(heading):
        return "exercise"
    return "content"


def is_section_heading(item: dict) -> bool:
    if item["kind"] != "text" or item["label"] != "section_header":
        return False
    h = item["text"]
    if not h or len(h) < 3:
        return False
    # Numbered sections, ALL-CAPS majors, or a known box/objectives heading.
    return bool(
        NUM_SECTION.match(h)
        or CHAPTER_OBJECTIVES.search(h)
        or any(pat.search(h) for _, pat in BOX)
        or (h.isupper() and len(h) > 4)
    )


def main() -> None:
    items = ordered_items()

    # Find content start: first chapter-objectives list or first "1.1" section.
    start_idx = 0
    for i, it in enumerate(items):
        if it["kind"] == "text" and (
            CHAPTER_OBJECTIVES.search(it["text"])
            or re.match(r"^1\.1\b", it["text"])
        ):
            start_idx = i
            break
    items = items[start_idx:]

    chunks: list[dict] = []
    cur = None  # current open chunk
    chapter = None

    def flush():
        nonlocal cur
        if cur and cur["text"].strip():
            cur["text"] = cur["text"].strip()
            cur["n_chars"] = len(cur["text"])
            cur["page_end"] = cur.get("page_end", cur["page_start"])
            if cur["n_chars"] >= 40:  # drop tiny fragments
                chunks.append(cur)
        cur = None

    for it in items:
        if is_section_heading(it):
            flush()
            heading = it["text"]
            btype = block_type_of(heading)
            sec_no = heading.split()[0] if NUM_SECTION.match(heading) else ""
            if sec_no:
                ch = chapter_of(sec_no)
                if ch:
                    chapter = ch
            cur = {
                "id": f"c{len(chunks):04d}",
                "chapter": chapter,
                "section_no": sec_no,
                "title": heading,
                "block_type": btype,
                "page_start": it["page"],
                "page_end": it["page"],
                "text": heading + "\n",
                "figure_pages": [],
            }
        elif cur is not None:
            if it["kind"] == "text" and it["text"]:
                cur["text"] += it["text"] + "\n"
                cur["page_end"] = it["page"]
            elif it["kind"] == "picture":
                if it["page"] not in cur["figure_pages"]:
                    cur["figure_pages"].append(it["page"])
    flush()

    with open(OUT, "w", encoding="utf-8") as f:
        for c in chunks:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")

    # Summary
    import collections
    by_type = collections.Counter(c["block_type"] for c in chunks)
    by_chap = collections.Counter(c["chapter"] for c in chunks)
    print(f"Wrote {len(chunks)} chunks -> {OUT}")
    print(f"  by block_type: {dict(by_type)}")
    print(f"  by chapter   : {dict(sorted(by_chap.items(), key=lambda x: (x[0] is None, x[0])))}")
    lens = [c["n_chars"] for c in chunks]
    print(f"  chars: min={min(lens)} median={sorted(lens)[len(lens)//2]} max={max(lens)}")


if __name__ == "__main__":
    main()
