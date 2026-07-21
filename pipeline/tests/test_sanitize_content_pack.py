import pathlib
import sqlite3
import tempfile
import unittest

from src import sanitize_content_pack as scp
from src.content_validation import scaffolding_reference_issues

# Column order must match the shipped schema (src/build_content_db.py).
_SCHEMA = """
CREATE TABLE topics (
    id TEXT PRIMARY KEY, chapter INTEGER, section_no TEXT,
    title TEXT, summary TEXT, slos TEXT, n_items INTEGER);
CREATE TABLE mcq_items (
    id TEXT PRIMARY KEY, topic_id TEXT, difficulty TEXT, bloom TEXT,
    stem TEXT, option_a TEXT, option_b TEXT, option_c TEXT, option_d TEXT,
    answer TEXT, rationale TEXT, verify_status TEXT);
CREATE TABLE plan_sections (
    id TEXT PRIMARY KEY, topic_id TEXT, section TEXT,
    variant_label TEXT, minutes INTEGER, body TEXT, materials TEXT);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
"""

# Synthetic flagged body per expected id. The migration does not depend on the exact
# production wording — only that each expected variant is flagged, becomes clean, and
# does so idempotently — so representative leaks exercise every invariant.
_DIRTY = "- Recall the key idea. (Excerpt 3)\n- Use Figure 2.1 from the textbook."
_CLEAN_ROWS = {
    "topicZ-explain-0": "Draw and label a simple circuit on the board.",
    "topicZ-engage-0": "Ask what students already know about magnets.",
}


def _make_dirty_pack(path: pathlib.Path, *, omit=None, dirty_body=_DIRTY):
    con = sqlite3.connect(path)
    con.executescript(_SCHEMA)
    for rid in scp.EXPECTED_UNSAFE_IDS:
        if rid == omit:
            continue
        con.execute("INSERT INTO plan_sections VALUES (?,?,?,?,?,?,?)",
                    (rid, "t", "explain", "v", 10, dirty_body, "[]"))
    for rid, body in _CLEAN_ROWS.items():
        con.execute("INSERT INTO plan_sections VALUES (?,?,?,?,?,?,?)",
                    (rid, "t", "explain", "v", 10, body, "[]"))
    con.execute("INSERT INTO meta VALUES ('pack_version', '1.0')")
    con.commit()
    con.close()


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.pack = self.dir / "content_pack.db"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.dir, ignore_errors=True)

    def _bodies(self):
        con = sqlite3.connect(f"file:{self.pack}?mode=ro", uri=True)
        con.row_factory = sqlite3.Row
        rows = {r["id"]: r["body"] for r in con.execute("SELECT id, body FROM plan_sections")}
        con.close()
        return rows

    def test_expected_id_set_is_23(self):
        self.assertEqual(len(scp.EXPECTED_UNSAFE_IDS), 23)

    def test_changes_exactly_expected_variants_and_leaves_clean_rows(self):
        _make_dirty_pack(self.pack)
        before = self._bodies()
        result = scp.migrate(self.pack)
        after = self._bodies()

        self.assertEqual(result["n_changed"], 23)
        self.assertEqual(set(result["changed"]), set(scp.EXPECTED_UNSAFE_IDS))
        changed = {rid for rid in before if before[rid] != after[rid]}
        self.assertEqual(changed, set(scp.EXPECTED_UNSAFE_IDS))
        # clean rows are byte-for-byte identical
        for rid in _CLEAN_ROWS:
            self.assertEqual(after[rid], before[rid])
        # nothing in the pack remains flagged
        self.assertEqual([rid for rid, b in after.items()
                          if scaffolding_reference_issues(b)], [])

    def test_fail_closed_when_already_clean(self):
        _make_dirty_pack(self.pack)
        scp.migrate(self.pack)                       # first pass sanitises
        with self.assertRaises(scp.MigrationError):  # second pass: nothing would change
            scp.migrate(self.pack)

    def test_fail_closed_when_expected_variant_missing(self):
        _make_dirty_pack(self.pack, omit=sorted(scp.EXPECTED_UNSAFE_IDS)[0])
        with self.assertRaises(scp.MigrationError):
            scp.migrate(self.pack)

    def test_fail_closed_on_unexpected_schema(self):
        _make_dirty_pack(self.pack)
        con = sqlite3.connect(self.pack)
        con.execute("ALTER TABLE plan_sections ADD COLUMN extra TEXT")
        con.commit()
        con.close()
        with self.assertRaises(scp.MigrationError):
            scp.migrate(self.pack)


if __name__ == "__main__":
    unittest.main()
