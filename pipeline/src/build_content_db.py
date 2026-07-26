"""Assemble the shipped content pack from the finished checkpoints.

Separate from `gen_content.py` on purpose: generation never writes to the database, so
a crashed or half-finished run can never corrupt the asset the app ships. This step is
idempotent — run it as often as you like, including while generation is still going
(it simply packs whatever topics are complete so far).

Emits:
  app/assets/content/content_pack.db   the bundled pack (topics + MCQ bank + 5E variants)
  data/processed/content/review.html   a human spot-check report (read this before shipping)

Run: uv run python -m src.build_content_db
"""

from __future__ import annotations

import html
import json
import pathlib
import sqlite3
import sys

from . import checkpoint as ckpt
from .gen_content import PLAN_MINUTES
from .topics import load_topics

REPO = pathlib.Path(__file__).resolve().parents[2]
PACK = REPO / "app" / "assets" / "content" / "content_pack.db"
REVIEW = ckpt.ROOT / "review.html"
PACK_VERSION = "1.0"

SCHEMA = """
CREATE TABLE topics (
    id TEXT PRIMARY KEY, chapter INTEGER, section_no TEXT,
    title TEXT, summary TEXT, slos TEXT, n_items INTEGER);

CREATE TABLE mcq_items (
    id TEXT PRIMARY KEY, topic_id TEXT, difficulty TEXT, bloom TEXT,
    stem TEXT, option_a TEXT, option_b TEXT, option_c TEXT, option_d TEXT,
    answer TEXT, rationale TEXT, verify_status TEXT);
CREATE INDEX idx_items_topic ON mcq_items(topic_id, difficulty);

CREATE TABLE plan_sections (
    id TEXT PRIMARY KEY, topic_id TEXT, section TEXT,
    variant_label TEXT, minutes INTEGER, body TEXT, materials TEXT);
CREATE INDEX idx_sections_topic ON plan_sections(topic_id, section);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
"""


def build() -> None:
    topics = load_topics()
    PACK.parent.mkdir(parents=True, exist_ok=True)
    if PACK.exists():
        PACK.unlink()
    con = sqlite3.connect(PACK)
    con.executescript(SCHEMA)

    n_topics = n_items = n_flagged = n_sections = 0
    skipped: list[str] = []
    review: list[dict] = []

    for t in topics:
        tid = t["id"]
        meta = ckpt.load("topic_meta", tid)
        verified = ckpt.load("mcq_verify", tid)
        plan = ckpt.load("plan_gen", tid)
        plan_verification = ckpt.load("plan_verify", tid)
        if not (meta and verified and plan and plan_verification):
            skipped.append(tid)
            continue
        # Only shippable items: flagged MCQs await human review and must not
        # reach a printed answer key. Plan variants flagged by plan_verify are
        # excluded individually; a topic ships only if every required section still
        # has at least one safe variant.
        items = [i for i in verified["items"] if i["verify_status"] == "passed"]
        flagged = [i for i in verified["items"] if i["verify_status"] == "flagged"]
        flagged_variants = {
            (item["section"], item["label"])
            for item in plan_verification.get("flagged", [])
        }
        rows = []
        safe_sections: set[str] = set()
        for section, variants in plan["sections"].items():
            for n, variant in enumerate(variants):
                if (section, variant["label"]) in flagged_variants:
                    continue
                rows.append((
                    f"{tid}-{section}-{n}", tid, section, variant["label"],
                    PLAN_MINUTES.get(section, 0), variant["body"],
                    json.dumps(variant.get("materials", [])),
                ))
                safe_sections.add(section)
        missing_sections = sorted(set(plan["sections"]) - safe_sections)
        if missing_sections:
            skipped.append(
                f"{tid} (no safe variant for: {', '.join(missing_sections)})"
            )
            continue

        con.execute(
            "INSERT INTO topics VALUES (?,?,?,?,?,?,?)",
            (tid, t["chapter"], t["section_no"], meta["title"], meta["summary"],
             json.dumps(meta["slos"]), len(items)),
        )
        con.executemany(
            "INSERT INTO mcq_items VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            [(f"{tid}-q{n:03d}", tid, item["difficulty"], item["bloom"],
              item["stem"], item["option_a"], item["option_b"],
              item["option_c"], item["option_d"], item["answer"],
              item["rationale"], item["verify_status"])
             for n, item in enumerate(items)],
        )
        con.executemany("INSERT INTO plan_sections VALUES (?,?,?,?,?,?,?)", rows)

        n_topics += 1
        n_items += len(items)
        n_flagged += len(flagged)
        n_sections += len(rows)
        review.append({
            "topic": meta["title"],
            "id": tid,
            "n_items": len(items),
            "items": items,
            "flagged": flagged,
            "rejected": verified.get("rejected", []),
            "excluded_plan_variants": plan_verification.get("flagged", []),
        })

    con.executemany("INSERT INTO meta VALUES (?,?)", [
        ("pack_version", PACK_VERSION),
        ("n_topics", str(n_topics)),
        ("n_items", str(n_items)),
        ("source", "PCTB Class 6 General Science (SNC)"),
    ])
    con.commit()
    con.close()

    print(f"Wrote {PACK} ({PACK.stat().st_size // 1024} KB)")
    print(f"  {n_topics} topics · {n_items} verified MCQs · {n_sections} plan variants")
    if n_flagged:
        print(f"  {n_flagged} items flagged for review (held back — not in the pack)")
    if skipped:
        print(f"  {len(skipped)} topics incomplete, not packed: {', '.join(skipped[:5])}"
              + (" …" if len(skipped) > 5 else ""))

    write_review(review)


def write_review(review: list[dict]) -> None:
    """The spot-check report. ADR-006 and the 3-week plan both call for a human (ideally a
    teacher) to review generated content before the demo — this is what they read."""
    e = html.escape
    parts = [
        "<meta charset='utf-8'><style>body{font:14px/1.5 system-ui;margin:2rem;max-width:60rem}"
        "h2{margin-top:2rem;border-bottom:1px solid #ccc}.q{margin:.6rem 0;padding:.6rem;"
        "border-left:3px solid #ddd}.flag{border-color:#e8a33d;background:#fff8ec}"
        ".rej{border-color:#d33;background:#fff0f0}.a{color:#137333;font-weight:600}"
        "small{color:#666}</style>",
        "<h1>Bayaz AI — content pack review</h1>",
        "<p>Check the <span class='a'>answer</span> of a sample against the textbook. "
        "Orange = flagged by the verifier (held back from the pack). "
        "Red = rejected.</p>",
    ]
    for r in review:
        parts.append(f"<h2>{e(r['topic'])} <small>{e(r['id'])} · {r['n_items']} items</small></h2>")
        for kind, cls, items in (("", "q", r["items"]), ("FLAGGED", "q flag", r["flagged"]),
                                 ("REJECTED", "q rej", r["rejected"])):
            for i in items:
                opts = " · ".join(
                    f"<b>{L})</b> {e(i['option_' + L.lower()])}" for L in "ABCD")
                note = f" <small>{e(i.get('verify_note', ''))}</small>" if kind else ""
                parts.append(
                    f"<div class='{cls}'><b>{e(kind)}</b> {e(i['stem'])}<br>{opts}<br>"
                    f"<span class='a'>ANSWER: {e(i['answer'])}</span> "
                    f"<small>[{e(i['difficulty'])}/{e(i['bloom'])}] {e(i['rationale'])}</small>"
                    f"{note}</div>")
    REVIEW.parent.mkdir(parents=True, exist_ok=True)
    REVIEW.write_text("\n".join(parts), encoding="utf-8")
    print(f"Wrote {REVIEW}")


if __name__ == "__main__":
    build()
    sys.exit(0)
