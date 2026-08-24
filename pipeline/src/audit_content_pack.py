"""Audit a built Bayaz curriculum pack before it is approved for release.

The command is read-only. It reports structural integrity, thin topic banks,
answer-position bias, normalized duplicate stems, duplicate section numbers,
and plan-section completeness. It exits non-zero only for structural release
blockers; quality warnings remain visible for human review.

Run from ``pipeline`` with::

    uv run python -m src.audit_content_pack --markdown ../docs/content/CURRENT_PACK_AUDIT.md
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import re
import sqlite3
import sys

from .content_validation import scaffolding_reference_issues

REPO = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_PACK = REPO / "app" / "assets" / "content" / "content_pack.db"
REQUIRED_PLAN_SECTIONS = {
    "objectives", "revision_starter", "engage", "explore", "explain",
    "socratic", "elaborate", "evaluate", "differentiation", "homework", "notes",
}


def normalize_stem(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def audit(path: pathlib.Path) -> tuple[dict, list[str]]:
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    failures: list[str] = []
    integrity = con.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok":
        failures.append(f"SQLite integrity check failed: {integrity}")

    topics = con.execute(
        "SELECT id, chapter, section_no, title, n_items FROM topics "
        "ORDER BY chapter, section_no"
    ).fetchall()
    item_count = con.execute(
        "SELECT COUNT(*) FROM mcq_items WHERE verify_status='passed'"
    ).fetchone()[0]
    answer_counts = dict(con.execute(
        "SELECT answer, COUNT(*) FROM mcq_items WHERE verify_status='passed' "
        "GROUP BY answer ORDER BY answer"
    ).fetchall())
    thin_topics = [dict(row) for row in topics if row["n_items"] < 10]

    duplicate_sections = []
    section_groups: dict[tuple[int, str], list[sqlite3.Row]] = collections.defaultdict(list)
    for row in topics:
        section_groups[(row["chapter"], row["section_no"])].append(row)
    for (chapter, section), rows in section_groups.items():
        if len(rows) > 1:
            duplicate_sections.append({
                "chapter": chapter,
                "section_no": section,
                "topics": [row["title"] for row in rows],
            })

    stem_groups: dict[str, list[dict]] = collections.defaultdict(list)
    for row in con.execute(
        "SELECT id, topic_id, stem FROM mcq_items WHERE verify_status='passed'"
    ):
        stem_groups[normalize_stem(row["stem"])].append(dict(row))
    duplicate_stems = [rows for rows in stem_groups.values() if len(rows) > 1]

    unsafe_plan_variants = []
    for row in con.execute(
        "SELECT id, topic_id, section, variant_label, body FROM plan_sections"
    ):
        issues = scaffolding_reference_issues(row["body"])
        if issues:
            unsafe_plan_variants.append({
                "id": row["id"],
                "topic_id": row["topic_id"],
                "section": row["section"],
                "variant_label": row["variant_label"],
                "issues": issues,
            })
    if any("excerpt" in item["issues"] for item in unsafe_plan_variants):
        failures.append(
            "Lesson-plan variants still expose internal excerpt references; "
            "regenerate the pack from verified checkpoints before release"
        )

    incomplete_plans = []
    for topic in topics:
        sections = {
            row[0] for row in con.execute(
                "SELECT DISTINCT section FROM plan_sections WHERE topic_id=?",
                (topic["id"],),
            )
        }
        missing = sorted(REQUIRED_PLAN_SECTIONS - sections)
        if missing:
            incomplete_plans.append({
                "topic_id": topic["id"],
                "topic": topic["title"],
                "missing": missing,
            })
    if incomplete_plans:
        failures.append(f"{len(incomplete_plans)} topics have incomplete lesson plans")

    report = {
        "pack": str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path),
        "integrity": integrity,
        "topic_count": len(topics),
        "verified_item_count": item_count,
        "answer_counts": answer_counts,
        "answer_percentages": {
            answer: round(count * 100 / item_count, 2) if item_count else 0
            for answer, count in answer_counts.items()
        },
        "thin_topics": thin_topics,
        "normalized_duplicate_stem_groups": len(duplicate_stems),
        "normalized_duplicate_stem_items": sum(len(group) for group in duplicate_stems),
        "duplicate_stem_examples": duplicate_stems[:20],
        "duplicate_section_numbers": duplicate_sections,
        "unsafe_plan_variant_count": len(unsafe_plan_variants),
        "unsafe_plan_variant_examples": unsafe_plan_variants[:30],
        "incomplete_plans": incomplete_plans,
    }
    con.close()
    return report, failures


def markdown(report: dict, failures: list[str]) -> str:
    lines = [
        "# Current curriculum pack audit",
        "",
        f"Pack: `{report['pack']}`",
        "",
        f"- SQLite integrity: **{report['integrity']}**",
        f"- Topics: **{report['topic_count']}**",
        f"- Verified MCQs: **{report['verified_item_count']}**",
        f"- Duplicate normalized stem groups: **{report['normalized_duplicate_stem_groups']}** "
        f"({report['normalized_duplicate_stem_items']} items)",
        "",
        "## Answer positions in the source bank",
        "",
        "| Position | Count | Percentage |",
        "|---|---:|---:|",
    ]
    for answer, count in report["answer_counts"].items():
        lines.append(
            f"| {answer} | {count} | {report['answer_percentages'][answer]:.2f}% |"
        )
    lines += [
        "",
        "The application now repositions correct answers into balanced per-paper targets "
        "when option wording is position-independent. Source-bank bias must still be "
        "reduced during the next content regeneration and human review.",
        "",
        "## Thin question banks",
        "",
    ]
    if report["thin_topics"]:
        for topic in report["thin_topics"]:
            lines.append(f"- {topic['title']}: {topic['n_items']} verified items")
    else:
        lines.append("None.")
    lines += ["", "## Duplicate section numbers", ""]
    if report["duplicate_section_numbers"]:
        for group in report["duplicate_section_numbers"]:
            lines.append(
                f"- Chapter {group['chapter']} / {group['section_no']}: "
                + "; ".join(group["topics"])
            )
    else:
        lines.append("None.")
    lines += [
        "",
        "## Lesson-plan reference warnings",
        "",
        f"- Variants with internal excerpt, figure, table, or cross-variant references: "
        f"**{report['unsafe_plan_variant_count']}**",
    ]
    for item in report["unsafe_plan_variant_examples"][:12]:
        lines.append(
            f"- `{item['id']}`: {', '.join(item['issues'])}"
        )
    lines += ["", "## Release blockers", ""]
    lines.extend(f"- {failure}" for failure in failures)
    if not failures:
        lines.append("No structural release blockers were detected by this audit.")
    lines += [
        "",
        "## Required release review",
        "",
        "Automated checks do not establish educational correctness. A subject teacher must "
        "review representative questions, all answer keys, rationales, lesson instructions, "
        "materials, references, and culturally/contextually sensitive content before release.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", type=pathlib.Path, default=DEFAULT_PACK)
    parser.add_argument("--json", type=pathlib.Path)
    parser.add_argument("--markdown", type=pathlib.Path)
    args = parser.parse_args()

    report, failures = audit(args.pack)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2), encoding="utf-8")
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(markdown(report, failures), encoding="utf-8")
    print(json.dumps(report, indent=2))
    if failures:
        print("Release blockers:", *failures, sep="\n- ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
