"""Crash-safe checkpointing for the build-time content run.

The content generation is an unattended, multi-hour GPU run on a laptop that may
sleep, lose power, or OOM. **No completed work may be lost, and no partial work may
be mistaken for completed work.** This mirrors the resume idiom `src/parse.py`
already uses for the 2-hour Docling pass: write one file per unit of work, and on
re-run skip any unit whose file is already there.

  * A **unit** is one `(stage, topic_id)` pair — e.g. `("mcq_gen", "ch04-4_1-e09b")`.
  * Each unit writes `data/processed/content/<stage>/<topic_id>.json`, written
    **atomically** (temp file + `os.replace`, which is atomic on POSIX). A process
    killed mid-write therefore leaves either the old file or the new one — never a
    truncated file that a resume would trust and skip.
  * `done()` additionally *parses* the file. A file that exists but does not parse
    (e.g. disk filled) is treated as not-done and regenerated, so corruption is
    self-healing rather than sticky.
  * `manifest.jsonl` is an append-only log for reporting only. **The unit files are
    the source of truth** — losing the manifest costs nothing.

The final `content_pack.db` is built by a separate, idempotent step that reads the
finished unit files, so an interrupted generation can never corrupt the shipped asset.
"""

from __future__ import annotations

import json
import os
import pathlib
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parents[2]
ROOT = REPO / "data" / "processed" / "content"
MANIFEST = ROOT / "manifest.jsonl"

STAGES = ("topic_meta", "mcq_gen", "mcq_verify", "plan_gen", "plan_verify")


def path(stage: str, topic_id: str) -> pathlib.Path:
    return ROOT / stage / f"{topic_id}.json"


def load(stage: str, topic_id: str) -> dict | None:
    """Return the unit's payload, or None if absent/corrupt (-> regenerate)."""
    p = path(stage, topic_id)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        print(f"    corrupt checkpoint {p.name} — discarding, will redo")
        p.unlink(missing_ok=True)
        return None


def done(stage: str, topic_id: str) -> bool:
    return load(stage, topic_id) is not None


def save(stage: str, topic_id: str, payload: dict, *, wall_s: float = 0.0) -> None:
    """Atomically publish a completed unit, then log it."""
    p = path(stage, topic_id)
    p.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(payload, indent=2, ensure_ascii=False)

    fd, tmp = tempfile.mkstemp(dir=p.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(body)
            f.flush()
            os.fsync(f.fileno())  # survive a power cut, not just a process kill
        os.replace(tmp, p)  # atomic
    except BaseException:
        pathlib.Path(tmp).unlink(missing_ok=True)
        raise

    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with open(MANIFEST, "a", encoding="utf-8") as f:
        f.write(json.dumps({
            "stage": stage,
            "topic_id": topic_id,
            "wall_s": round(wall_s, 1),
            "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }) + "\n")


def clear(stage: str, topic_id: str | None = None) -> int:
    """Drop checkpoints so `--force` / `--stage` can redo a slice."""
    if topic_id:
        p = path(stage, topic_id)
        existed = p.exists()
        p.unlink(missing_ok=True)
        return int(existed)
    d = ROOT / stage
    if not d.is_dir():
        return 0
    n = 0
    for p in d.glob("*.json"):
        p.unlink()
        n += 1
    return n


def progress(topic_ids: list[str]) -> dict[str, tuple[int, int]]:
    """{stage: (done, total)} — what a resumed run still has to do."""
    return {s: (sum(done(s, t) for t in topic_ids), len(topic_ids)) for s in STAGES}
