"""Deterministically sanitise the shipped content pack in place.

Why this exists (and why it is *not* `build_content_db`): the canonical pipeline
rebuilds the pack from approved generation checkpoints. Those checkpoints — and the
processed source corpus they were produced from — are not included in this repository
archive, so the pack cannot be regenerated from verified checkpoints here. This step
is the honest fallback: it repairs the exact leaked scaffolding references that the
audit flags, directly on the packaged database, without a generation run.

It never edits the shipped file with ad-hoc SQL. It copies the pack to a temporary
database, updates only the known-unsafe lesson-plan variants through the deterministic
`sanitize_plan_body`, then refuses to publish unless every safety invariant holds:

  * the `plan_sections` schema is exactly as expected;
  * every expected unsafe variant id is present;
  * exactly the expected variants change — no more, no fewer;
  * no other row (any table) changes value;
  * every changed variant is clean afterwards (`scaffolding_reference_issues == []`);
  * the transformation is idempotent;
  * SQLite `integrity_check` is ok.

Only then is the temporary database swapped into place atomically. Any failure raises
and leaves the shipped pack untouched.

Run: uv run python -m src.sanitize_content_pack
"""

from __future__ import annotations

import os
import pathlib
import shutil
import sqlite3
import tempfile

from .content_validation import sanitize_plan_body, scaffolding_reference_issues

REPO = pathlib.Path(__file__).resolve().parents[2]
PACK = REPO / "app" / "assets" / "content" / "content_pack.db"

# The 23 lesson-plan variants the audit flags for internal excerpt / figure / table
# references. Enumerated explicitly so the migration fails closed if the pack drifts.
EXPECTED_UNSAFE_IDS = frozenset({
    "ch01-1_2_1-2b0a-explore-2",
    "ch01-1_2_2-2791-explain-0",
    "ch03-3_2_2-cd0e-revision_starter-0",
    "ch03-3_2_2-cd0e-revision_starter-1",
    "ch03-3_2_2-cd0e-engage-1",
    "ch03-3_2_2-cd0e-explain-0",
    "ch03-3_2_2-cd0e-elaborate-0",
    "ch03-3_2_2-cd0e-elaborate-1",
    "ch03-3_2_2-cd0e-evaluate-0",
    "ch03-3_2_2-cd0e-evaluate-1",
    "ch03-3_2_2-cd0e-homework-0",
    "ch03-3_2_2-cd0e-homework-1",
    "ch03-3_3-e786-objectives-0",
    "ch03-3_3-e786-objectives-1",
    "ch05-5_1-806b-explain-0",
    "ch05-5_3-ad06-explain-0",
    "ch09-9_2-1d7b-explain-0",
    "ch10-10_1_1-d401-explain-0",
    "ch11-11_2_1-c666-revision_starter-0",
    "ch11-11_3-688d-revision_starter-0",
    "ch11-11_3-688d-revision_starter-1",
    "ch11-11_3_1-1e91-explore-1",
    "ch12-12_3_4-b133-explain-0",
})

EXPECTED_PLAN_COLUMNS = (
    "id", "topic_id", "section", "variant_label", "minutes", "body", "materials",
)


class MigrationError(RuntimeError):
    """A safety invariant failed; the shipped pack must be left untouched."""


def _plan_columns(con: sqlite3.Connection) -> tuple[str, ...]:
    return tuple(r[1] for r in con.execute("PRAGMA table_info(plan_sections)"))


def _snapshot(con: sqlite3.Connection) -> dict[str, dict]:
    """Every table's rows keyed by primary id, as plain dicts, for value comparison."""
    snap: dict[str, dict] = {}
    tables = [r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    for table in tables:
        con.row_factory = sqlite3.Row
        rows = con.execute(f"SELECT * FROM {table}").fetchall()
        key = rows[0].keys()[0] if rows else "id"
        snap[table] = {r[key]: dict(r) for r in rows}
    return snap


def migrate(pack: pathlib.Path = PACK) -> dict:
    if not pack.exists():
        raise MigrationError(f"pack not found: {pack}")

    # Explicit close (not a `with` block): sqlite3's context manager commits but leaves
    # the connection — and on Windows the file lock — open, which would block os.replace.
    src = sqlite3.connect(f"file:{pack}?mode=ro", uri=True)
    try:
        columns = _plan_columns(src)
        if columns != EXPECTED_PLAN_COLUMNS:
            raise MigrationError(
                f"unexpected plan_sections schema: {columns} != {EXPECTED_PLAN_COLUMNS}")
        before = _snapshot(src)
    finally:
        src.close()

    plan_before = before["plan_sections"]
    missing = EXPECTED_UNSAFE_IDS - plan_before.keys()
    if missing:
        raise MigrationError(f"expected unsafe variants absent from pack: {sorted(missing)}")

    # 1-3. Copy the pack to a temporary database beside it (same filesystem, so the
    # final os.replace is atomic). All work happens on the copy.
    fd, tmp_name = tempfile.mkstemp(dir=pack.parent, suffix=".db.tmp")
    os.close(fd)
    tmp = pathlib.Path(tmp_name)
    try:
        shutil.copy2(pack, tmp)

        changed: list[str] = []
        con = sqlite3.connect(tmp)
        try:
            for row_id, row in plan_before.items():
                body = row["body"]
                new_body = sanitize_plan_body(body)
                if row_id in EXPECTED_UNSAFE_IDS:
                    # 4. Update only the identified unsafe variants.
                    if new_body == body:
                        raise MigrationError(
                            f"{row_id}: expected a change but body was unaffected")
                    if scaffolding_reference_issues(new_body):
                        raise MigrationError(
                            f"{row_id}: still flagged after sanitising: {new_body!r}")
                    if sanitize_plan_body(new_body) != new_body:
                        raise MigrationError(f"{row_id}: sanitiser is not idempotent")
                    con.execute(
                        "UPDATE plan_sections SET body=? WHERE id=?", (new_body, row_id))
                    changed.append(row_id)
                elif new_body != body:
                    # A row we did not expect to touch would change — refuse.
                    raise MigrationError(f"clean row would change: {row_id}")
            con.commit()

            # 5. Exactly the expected variants changed.
            if set(changed) != set(EXPECTED_UNSAFE_IDS):
                raise MigrationError(
                    f"changed set mismatch: {sorted(set(changed) ^ EXPECTED_UNSAFE_IDS)}")

            # 7. Integrity.
            integrity = con.execute("PRAGMA integrity_check").fetchone()[0]
            if integrity != "ok":
                raise MigrationError(f"integrity_check failed: {integrity}")

            after = _snapshot(con)
        finally:
            con.close()

        # 6. Every other row, every table, unchanged by value.
        if after.keys() != before.keys():
            raise MigrationError("table set changed")
        for table, rows_after in after.items():
            rows_before = before[table]
            if rows_after.keys() != rows_before.keys():
                raise MigrationError(f"{table}: row id set changed")
            for rid, ra in rows_after.items():
                rb = rows_before[rid]
                if table == "plan_sections" and rid in EXPECTED_UNSAFE_IDS:
                    # only `body` may differ on the expected variants
                    if {k: v for k, v in ra.items() if k != "body"} != \
                       {k: v for k, v in rb.items() if k != "body"}:
                        raise MigrationError(f"{rid}: a non-body column changed")
                    continue
                if ra != rb:
                    raise MigrationError(f"{table}:{rid}: value changed unexpectedly")

        # 8-9. No unsafe variant remains anywhere in the pack.
        still = [rid for rid, r in after["plan_sections"].items()
                 if scaffolding_reference_issues(r["body"])]
        if still:
            raise MigrationError(f"unsafe variants remain: {sorted(still)}")

        # 10. Publish atomically.
        os.replace(tmp, pack)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise

    return {"changed": sorted(changed), "n_changed": len(changed), "integrity": "ok"}


def main() -> int:
    result = migrate()
    print(f"Sanitised {result['n_changed']} lesson-plan variants in {PACK}")
    for rid in result["changed"]:
        print(f"  · {rid}")
    print("integrity_check: ok · no other rows changed · zero unsafe variants remain")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
