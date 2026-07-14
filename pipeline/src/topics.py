"""Topic catalogue — the teachable units of the Class-6 General Science book.

Derives a stable, deterministic list of topics from `curriculum.db` (the same
corpus the app retrieves over). This catalogue drives two things:

  1. the **build-time content pipeline** — one MCQ bank + one set of 5E section
     variants is generated per topic (see `gen_content.py`);
  2. the app's **topic picker**, replacing today's free-text box.

Two clean-ups happen here, because the source titles come from OCR of a scanned,
watermarked book and are not fit to show a teacher or to use as a retrieval query:

  * **De-glued words.** OCR dropped spaces ("BALANCEDDIET", "Reproductionin
    Plants", "Giveshortanswers."). We split a suspicious token with wordninja,
    but only accept the split when the glued form does *not* appear as a real word
    in the textbook body and every piece of the split does. The book's own text is
    the arbiter, so genuine words survive ("Diarrhoea" stays "Diarrhoea").
  * **Exercise headings.** Chapter exercises are chunked as `block_type='content'`
    with titles like "Selectthe correct option." — they are questions, not
    teachable topics. Filtering runs *after* de-gluing, so the glued forms match too.

Run: uv run python -m src.topics          # print the catalogue
"""

from __future__ import annotations

import functools
import hashlib
import re
import sqlite3
import sys

import wordninja

from .build_db import DB

# A teachable topic must carry a real section number ("4.1", "1.1.2"). This also
# drops the OCR debris ("6.2):", empty section numbers).
SECTION_NO = re.compile(r"^\d+(\.\d+)*$")

# Exercise/assessment headings that survive into `content` blocks. Applied to the
# *de-glued* title, so plain word boundaries are enough.
EXERCISE_TITLE = re.compile(
    r"encircle|select the|choose the|give (short |detailed )?answers?|"
    r"answers? in detail|write (short |detailed )?answers?|constructed response|"
    r"answer the following|briefly describe|fill in|differentiate between|"
    r"investigate|project|tick|match the",
    re.I,
)

# Lowercase words that should not be capitalised in a display title.
_MINOR = {"a", "an", "and", "as", "at", "between", "by", "for", "in", "of", "on",
          "or", "the", "to", "with"}


_OK_SINGLE = {"a", "i"}  # the only legitimate one-letter words


@functools.lru_cache(maxsize=1)
def _vocab() -> frozenset[str]:
    """Every word the textbook body uses. Validates the *pieces* of a split — it
    cannot decide whether to split, because the body contains the same OCR glue
    as the titles ("giveshortanswers" occurs 5x, "existindependently" 3x)."""
    con = sqlite3.connect(DB)
    words: set[str] = set()
    for (text,) in con.execute("SELECT text FROM chunks"):
        words.update(re.findall(r"[a-z]{2,}", (text or "").lower()))
    con.close()
    return frozenset(words)


def deglue(token: str) -> list[str]:
    """Split an OCR-glued token. wordninja decides *whether* the token is one real
    word (it returns a single piece for 'diarrhoea', 'geostationary', 'organelles'
    and splits 'staticelectricity', 'thesun', 'giveshortanswers'); the book's
    vocabulary then vetoes unconfident splits ('meteorids' -> 'meteor' + 'ids')."""
    low = token.lower()
    if len(low) < 6 or not low.isalpha():
        return [token]
    parts = wordninja.split(low)
    if len(parts) < 2:
        return [token]
    if any(p not in _vocab() and p not in _OK_SINGLE for p in parts):
        return [token]
    return parts


_LEADING_NUMBER = re.compile(r"^\d+(\.\d+)*\.?\s*")


def strip_leading_number(title: str) -> str:
    """Drop a hardcoded '1.2.1 ' / '3.2. ' prefix. The number is carried separately
    (`section_no`); a title should never repeat it, in the source or in an LLM rewrite
    that echoed the raw heading back verbatim."""
    return _LEADING_NUMBER.sub("", (title or "").strip())


def clean_title(raw: str) -> str:
    """OCR title -> a title a teacher would recognise. '3.2 BALANCEDDIET' -> 'Balanced Diet'.

    De-glues alphabetic *runs* rather than whitespace tokens, so trailing periods
    ("Giveshortanswers.") and internal hyphens ("Non-metals") survive intact.
    """
    # Drop the leading section number; it is carried separately.
    body = strip_leading_number(raw)
    body = re.sub(r"[A-Za-z]{6,}", lambda m: " ".join(deglue(m.group(0))), body)

    out = []
    for i, w in enumerate(body.split()):
        core = w.strip(".,:;?!()").lower()
        # ALLCAPS headings ("CELLS", "FOOD PYRAMID") are shouted section headers;
        # everything else keeps the book's own casing (its proper nouns are right).
        if w.isupper() and len(w) > 1:
            w = w.lower()
        if i > 0 and core in _MINOR:
            out.append(w.lower())
        else:
            out.append(w[0].upper() + w[1:] if w else w)
    return " ".join(out).strip(" .:")


def topic_id(chapter: int, section_no: str, title: str) -> str:
    """Stable across rebuilds. The title hash disambiguates the two '1.3.1' sections."""
    h = hashlib.sha1(title.encode("utf-8")).hexdigest()[:4]
    return f"ch{chapter:02d}-{section_no.replace('.', '_')}-{h}"


def load_topics() -> list[dict]:
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT chapter, section_no, title, id, length(text) FROM chunks "
        "WHERE block_type = 'content' ORDER BY chapter, section_no"
    ).fetchall()
    con.close()

    topics: dict[tuple, dict] = {}
    for chapter, section_no, title, chunk_id, n_chars in rows:
        if chapter is None or not section_no or not SECTION_NO.match(section_no.strip()):
            continue
        clean = clean_title(title)
        if not clean or EXERCISE_TITLE.search(clean):
            continue
        key = (chapter, section_no.strip(), title)
        t = topics.setdefault(key, {
            "id": topic_id(chapter, section_no.strip(), title),
            "chapter": chapter,
            "section_no": section_no.strip(),
            "raw_title": title,
            "title": clean,
            "chunk_ids": [],
            "n_chars": 0,
        })
        t["chunk_ids"].append(chunk_id)
        t["n_chars"] += n_chars or 0

    ordered = sorted(
        topics.values(),
        key=lambda t: (t["chapter"], [int(p) for p in t["section_no"].split(".")]),
    )
    # The retrieval query the app would issue for this topic. Titles alone are
    # terse ("Fibre"), so anchor them in the subject for a sharper embedding.
    for t in ordered:
        t["query"] = f"{t['title']} (Class 6 General Science, Chapter {t['chapter']})"
    return ordered


def main(argv: list[str]) -> None:
    topics = load_topics()
    for t in topics:
        flag = "  ⚠ thin" if t["n_chars"] < 400 else ""
        print(f"{t['id']:<22} {t['section_no']:<8} {t['title']:<48} "
              f"{len(t['chunk_ids'])}ch {t['n_chars']}c{flag}")
    print(f"\n{len(topics)} topics across {len({t['chapter'] for t in topics})} chapters")


if __name__ == "__main__":
    main(sys.argv[1:])
