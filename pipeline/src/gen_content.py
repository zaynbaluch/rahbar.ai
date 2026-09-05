"""Build-time content generation — the MCQ bank + 5E section library, per topic.

Why this exists: generating on the phone costs ~3.5 min per test and is capped by a
1.2B model's quality (ADR-003). We generate the content **once, here, with a ~8B model
on the laptop GPU**, verify it, and ship it — so the app answers instantly and the
answer keys have actually been checked. See docs/decisions/ADR-008.

Stages, each checkpointed per topic so a crashed run resumes without losing work
(`src/checkpoint.py`):

    topic_meta  -> clean display title + summary + SLOs   (also fixes OCR-damaged headings)
    mcq_gen     -> ~60 candidate questions (over-generated; verification culls them)
    mcq_verify  -> judge each candidate; keep/flag/reject  (the answer-key safety gate)
    plan_gen    -> 5E section variants
    plan_verify -> groundedness check on each variant

Run (server must be up — see scripts/setup-genserver.sh):
    uv run python -m src.gen_content                      # all topics, resume
    uv run python -m src.gen_content --only ch04-4_1-e09b # one topic
    uv run python -m src.gen_content --stage mcq_gen --force
    uv run python -m src.gen_content --dry-run
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
import time

import numpy as np

from . import checkpoint as ckpt
from .content_validation import (
    has_material_citation, sanitize_plan_body, scaffolding_reference_issues,
)
from . import llm
from .build_db import DB, embed_texts, unpack
from .rag_prompt import REPO, _is_exercise
from .topics import load_topics, strip_leading_number

BUILD_PROMPTS = REPO / "prompts" / "build"

# Candidates to over-generate per topic. Verification and dedup cull them hard: on a *thin*
# section (e.g. 4.1 Digestion, ~1.8k chars of source) the model saturates the space of sensible
# questions at ~20 and then repeats itself, so pushing this higher just buys duplicates. Rich
# sections (Solutions, Alimentary Canal) yield far more from the same budget.
N_CANDIDATES = int(os.environ.get("RAHBAR_N_CANDIDATES", "45"))
N_PER_CALL = int(os.environ.get("RAHBAR_N_PER_CALL", "15"))  # per call, to fit the context
RETRIEVE_K = 8         # grounding excerpts per topic
DEDUP_THRESHOLD = 0.95 # cosine above which two stems are "the same question"

# The whole run has to fit an 8B Q4 in the 6 GB of an RTX 4050 (server runs at -c 8192).
# Budget the grounding so prompt + response always clear it: ~1.5k tokens of context
# leaves room for a ~3.5k-token plan response. Same shape as RagService's on-device
# budget (3000 chars / 1200 per excerpt), just roomier since we are off-device.
CONTEXT_CHAR_BUDGET = 6000
PER_EXCERPT_CHAR_CAP = 1200

# ADR-006 fixes the period budget. Minutes live here, not in the model's output, so
# that swapping any section variant in the app can never overrun the 50-minute period.
PLAN_MINUTES = {
    "objectives": 0, "revision_starter": 5, "engage": 5, "explore": 12,
    "explain": 12, "socratic": 0, "elaborate": 8, "evaluate": 8,
    "differentiation": 0, "homework": 0, "notes": 0,
}
PLAN_SECTIONS = list(PLAN_MINUTES)

# ---------------------------------------------------------------- JSON schemas

def _obj(props: dict, required: list[str]) -> dict:
    return {"type": "object", "properties": props, "required": required,
            "additionalProperties": False}


TOPIC_META_SCHEMA = _obj({
    "title": {"type": "string"},
    "summary": {"type": "string"},
    "slos": {"type": "array", "items": {"type": "string"}, "minItems": 3, "maxItems": 4},
}, ["title", "summary", "slos"])

_QUESTION = _obj({
    "stem": {"type": "string"},
    "option_a": {"type": "string"},
    "option_b": {"type": "string"},
    "option_c": {"type": "string"},
    "option_d": {"type": "string"},
    "answer": {"type": "string", "enum": ["A", "B", "C", "D"]},
    "difficulty": {"type": "string", "enum": ["easy", "medium", "hard"]},
    "bloom": {"type": "string", "enum": ["remember", "understand", "apply", "analyse"]},
    "rationale": {"type": "string"},
    "source_excerpt": {"type": "integer"},
}, ["stem", "option_a", "option_b", "option_c", "option_d", "answer",
    "difficulty", "bloom", "rationale", "source_excerpt"])

MCQ_SCHEMA = _obj({
    "questions": {"type": "array", "items": _QUESTION,
                  "minItems": 1, "maxItems": N_PER_CALL},
}, ["questions"])

VERIFY_SCHEMA = _obj({
    "verdict": {"type": "string", "enum": ["correct", "unsure", "wrong"]},
    "reason": {"type": "string"},
}, ["verdict", "reason"])

_VARIANT = _obj({
    "label": {"type": "string"},
    "body": {"type": "string"},
    "materials": {"type": "array", "items": {"type": "string"}},
}, ["label", "body", "materials"])

PLAN_SCHEMA = _obj({
    "sections": {"type": "array", "minItems": len(PLAN_SECTIONS),
                 "items": _obj({
                     "section": {"type": "string", "enum": PLAN_SECTIONS},
                     "variants": {"type": "array", "items": _VARIANT, "minItems": 1},
                 }, ["section", "variants"])},
}, ["sections"])

# ---------------------------------------------------------------- prompt loading


def load_prompt(name: str) -> tuple[str, str]:
    """Split a build prompt into (system, user) on its `## SYSTEM` / `## USER` headers —
    the same convention `dump_prompts.py` uses for the on-device templates."""
    text = (BUILD_PROMPTS / f"{name}.md").read_text(encoding="utf-8")
    _, _, rest = text.partition("## SYSTEM")
    system, _, user = rest.partition("## USER")
    return system.strip(), user.strip()


def fill(template: str, **kw) -> str:
    for k, v in kw.items():
        template = template.replace("{{" + k + "}}", str(v))
    return template

# ---------------------------------------------------------------- grounding


def own_chunks(topic: dict) -> list[tuple]:
    """The section's own chunks, in book order — what the topic *is*."""
    con = sqlite3.connect(DB)
    q = ",".join("?" * len(topic["chunk_ids"]))
    rows = con.execute(
        f"SELECT 0.0, id, chapter, section_no, title, block_type, page_start, page_end, text "
        f"FROM chunks WHERE id IN ({q})", topic["chunk_ids"]
    ).fetchall()
    con.close()
    return rows


def _context(hits: list[tuple]) -> str:
    """Render excerpts under the char budget. Same shape as `rag_prompt.build_context`,
    but capped — an over-long context would push the plan response past the server's
    8192-token window on a 6 GB GPU."""
    blocks, used = [], 0
    for i, h in enumerate(hits, 1):
        _, _cid, chapter, _sec, title, _bt, p0, p1, text = h
        t = (text or "").strip()
        if len(t) > PER_EXCERPT_CHAR_CAP:
            head = t[:PER_EXCERPT_CHAR_CAP]
            t = head[: head.rfind(".") + 1] or head  # cut on a sentence boundary
        if blocks and used + len(t) > CONTEXT_CHAR_BUDGET:
            break
        used += len(t)
        pages = f"p{p0}" if p0 == p1 else f"p{p0}-{p1}"
        blocks.append(f"[Excerpt {i} — Ch {chapter}, {title} ({pages})]\n{t}")
    return "\n\n".join(blocks)


def topic_context(topic: dict, k: int = RETRIEVE_K) -> str:
    """Grounding for one topic: its own chunks first (so the content is *about* the
    topic), then the nearest other chunks (which pull in the book's Activity boxes and
    related sections) up to k. Mirrors `RagService`'s retrieval, but anchored."""
    hits = list(own_chunks(topic))
    have = {h[1] for h in hits}

    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT id, chapter, section_no, title, block_type, page_start, page_end, "
        "text, embedding FROM chunks"
    ).fetchall()
    con.close()

    qv = embed_texts([topic["query"]])[0]
    scored = []
    for r in rows:
        if r[0] in have or _is_exercise(r[4], r[3]):
            continue
        scored.append((float(np.dot(qv, unpack(r[8]))), *r[:8]))
    scored.sort(reverse=True)

    hits.extend(scored[: max(0, k - len(hits))])
    return _context(hits)

# ---------------------------------------------------------------- stages


def run_topic_meta(topic: dict) -> dict:
    system, user = load_prompt("topic_meta")
    ctx = _context(list(own_chunks(topic)))
    out = llm.chat_json(
        system,
        fill(user, raw_title=topic["raw_title"], chapter=topic["chapter"],
             section_no=topic["section_no"], context=ctx),
        TOPIC_META_SCHEMA, max_tokens=1024, temperature=0.2,
    )
    # Belt-and-braces: the prompt asks the model to drop the section number, but it
    # sometimes echoes `raw_title` (which carries one) back verbatim. section_no is
    # already tracked on the topic — a title must never duplicate it.
    out["title"] = strip_leading_number(out["title"])
    return out


def _quota(n: int) -> list[tuple[int, int, int]]:
    """Split n candidates into per-call (easy, medium, hard) quotas at 40/40/20.

    Asking for a *mix* gets ignored — the first run came back 5 easy / 15 medium / 2 hard.
    Asking for exact counts per call does not."""
    calls = []
    left = n
    while left > 0:
        k = min(N_PER_CALL, left)
        easy = round(k * 0.4)
        hard = round(k * 0.2)
        calls.append((easy, k - easy - hard, hard))
        left -= k
    return calls


def run_mcq_gen(topic: dict, meta: dict) -> dict:
    system, user = load_prompt("mcq_bank")
    ctx = topic_context(topic)
    slos = "; ".join(meta["slos"])
    questions: list[dict] = []

    # Several smaller calls beat one huge one (the response stays inside the context), but
    # independent calls repeat themselves — the first run produced 24% near-duplicates. So
    # each call is shown what the previous ones already wrote and told to avoid it.
    for easy, medium, hard in _quota(N_CANDIDATES):
        n = easy + medium + hard
        avoid = ""
        if questions:
            written = "\n".join(f"- {q['stem']}" for q in questions)
            avoid = ("\n\nQuestions already in the bank for this topic. Do NOT repeat or "
                     f"rephrase any of them; test something different:\n{written}")
        out = llm.chat_json(
            system,
            fill(user, topic=meta["title"], chapter=topic["chapter"], slos=slos,
                 context=ctx, n=n, easy=easy, medium=medium, hard=hard) + avoid,
            MCQ_SCHEMA, max_tokens=6144, temperature=0.8,
        )
        got = out.get("questions", [])
        if not got:
            break
        questions.extend(got)
        print(f"    {len(questions)}/{N_CANDIDATES} candidates")
    return {"context": ctx, "questions": questions[:N_CANDIDATES]}


# The student sees only the printed paper, so any reference to the prompt's own scaffolding
# is a hard reject — a stem reading "according to the excerpts provided" would go to press.
LEAKAGE = ("excerpt", "the passage", "text above", "given material", "according to the text")
# Options must be candidate answers, not commentary about which answer is right.
META_OPTION = ("incorrect statement", "correct statement", "this is true", "this is false",
               "none of these is correct")


def _structural_reject(q: dict) -> str | None:
    """Cheap checks first — no need to spend a GPU call rejecting a malformed item."""
    opts = [q["option_a"], q["option_b"], q["option_c"], q["option_d"]]
    stripped = [o.strip().lower() for o in opts]
    stem = q["stem"].strip().lower()
    if any(not o for o in stripped):
        return "empty option"
    if len(set(stripped)) != 4:
        return "duplicate options"
    if not stem:
        return "empty stem"
    banned = ("all of the above", "none of the above", "both a and b", "all of these")
    if any(b in o for o in stripped for b in banned):
        return "banned option"
    if any(m in o for o in stripped for m in META_OPTION):
        return "option is commentary, not an answer"
    if any(leak in t for t in (stem, *stripped) for leak in LEAKAGE):
        return "leaks the prompt scaffolding into printed text"
    if " not " in f" {stem} " or "except" in stem:
        return "negative stem"
    if len(stem.split()) > 35:
        return "stem too long"
    return None


def _dedup(questions: list[dict]) -> list[dict]:
    """Drop near-identical stems so a sampled test never repeats itself (ADR-003 saw the
    on-device 1B emit Q1 ≈ Q6; the bank must not have that problem baked in)."""
    if not questions:
        return []
    vecs = embed_texts([q["stem"] for q in questions])
    keep: list[int] = []
    for i in range(len(questions)):
        if all(float(np.dot(vecs[i], vecs[j])) < DEDUP_THRESHOLD for j in keep):
            keep.append(i)
    return [questions[i] for i in keep]


def run_mcq_verify(topic: dict, gen: dict) -> dict:
    system, user = load_prompt("verify_mcq")
    ctx = gen["context"]

    # Order matters: structural (free) -> dedup (cheap) -> LLM judge (expensive). Verifying
    # a question we are about to discard as a duplicate is pure wasted GPU; on a thin topic
    # that is half the candidates.
    candidates, rejected = [], []
    for q in gen["questions"]:
        why = _structural_reject(q)
        if why:
            rejected.append({**q, "verify_status": "rejected", "verify_note": why})
        else:
            candidates.append(q)

    deduped = _dedup(candidates)
    n_dupes = len(candidates) - len(deduped)

    survivors = []
    for q in deduped:
        out = llm.chat_json(
            system,
            fill(user, context=ctx, stem=q["stem"], option_a=q["option_a"],
                 option_b=q["option_b"], option_c=q["option_c"], option_d=q["option_d"],
                 answer=q["answer"], rationale=q["rationale"]),
            VERIFY_SCHEMA, max_tokens=256, temperature=0.0,
        )
        verdict, reason = out["verdict"], out.get("reason", "")
        rec = {**q, "verify_status": {"correct": "passed", "unsure": "flagged",
                                      "wrong": "rejected"}[verdict],
               "verify_note": reason}
        (rejected if verdict == "wrong" else survivors).append(rec)

    passed = sum(r["verify_status"] == "passed" for r in survivors)
    print(f"    verified: {passed} passed, {len(survivors) - passed} flagged, "
          f"{len(rejected)} rejected, {n_dupes} duplicate")
    return {"items": survivors, "rejected": rejected,
            "stats": {"passed": passed, "flagged": len(survivors) - passed,
                      "rejected": len(rejected), "duplicates": n_dupes}}


def run_plan_gen(topic: dict, meta: dict) -> dict:
    system, user = load_prompt("plan_sections")
    ctx = topic_context(topic)
    out = llm.chat_json(
        system,
        fill(user, topic=meta["title"], chapter=topic["chapter"],
             slos="; ".join(meta["slos"]), context=ctx),
        PLAN_SCHEMA, max_tokens=8192, temperature=0.6,
    )
    sections = {s["section"]: s["variants"] for s in out["sections"]}
    missing = [s for s in PLAN_SECTIONS if not sections.get(s)]
    if missing:
        raise llm.LlmError(f"plan missing sections: {missing}")
    # Deterministically repair leaked grounding scaffolding ("(Excerpt 7)", "Use Figure
    # 5.6 from the textbook") before the checkpoint is written, so plan_verify judges the
    # teacher-visible text and does not exclude an otherwise good variant over a citation
    # tag. Anything sanitising cannot make self-contained stays flagged and is excluded.
    for variants in sections.values():
        for v in variants:
            v["body"] = sanitize_plan_body(v["body"])
    return {"context": ctx, "sections": sections}


def run_plan_verify(topic: dict, plan: dict) -> dict:
    """Groundedness + swap-safety. Cross-references are the one thing that would break
    variant swapping, and they are cheap to catch with a string check."""
    flagged = []
    for section, variants in plan["sections"].items():
        for v in variants:
            issues = scaffolding_reference_issues(v["body"])
            if issues:
                flagged.append({"section": section, "label": v["label"],
                                "note": f"bad reference: {', '.join(issues)}"})
            # Materials is a shopping list. A citation here ("Ch 4, 4.1.2 Alimentary
            # Canal") means the teacher is told to bring a textbook section to class.
            for m in v.get("materials", []):
                if has_material_citation(m):
                    flagged.append({"section": section, "label": v["label"],
                                    "note": f"materials contains a citation: {m!r}"})
                    break
    return {"flagged": flagged, "n_flagged": len(flagged)}

# ---------------------------------------------------------------- driver

STAGE_FNS = {
    "topic_meta": lambda t, s: run_topic_meta(t),
    "mcq_gen": lambda t, s: run_mcq_gen(t, s["topic_meta"]),
    "mcq_verify": lambda t, s: run_mcq_verify(t, s["mcq_gen"]),
    "plan_gen": lambda t, s: run_plan_gen(t, s["topic_meta"]),
    "plan_verify": lambda t, s: run_plan_verify(t, s["plan_gen"]),
}
DEPENDS = {"mcq_gen": ["topic_meta"], "mcq_verify": ["topic_meta", "mcq_gen"],
           "plan_gen": ["topic_meta"], "plan_verify": ["topic_meta", "plan_gen"]}


def run(topics: list[dict], stages: list[str], *, force: bool) -> None:
    for i, topic in enumerate(topics, 1):
        tid = topic["id"]
        print(f"\n[{i}/{len(topics)}] {tid}  {topic['title']}")
        state: dict[str, dict] = {}

        for stage in ckpt.STAGES:
            for dep in DEPENDS.get(stage, []):
                if dep not in state:
                    state[dep] = ckpt.load(dep, tid)

            if stage not in stages:
                if stage not in state:
                    state[stage] = ckpt.load(stage, tid)
                continue

            if not force and ckpt.done(stage, tid):
                state[stage] = ckpt.load(stage, tid)
                print(f"  · {stage}: cached")
                continue

            if any(state.get(d) is None for d in DEPENDS.get(stage, [])):
                print(f"  · {stage}: skipped (dependency missing — run it first)")
                continue

            print(f"  → {stage}")
            t0 = time.time()
            try:
                payload = STAGE_FNS[stage](topic, state)
            except llm.LlmError as e:
                # Leave the checkpoint unwritten: the unit stays "not done" and a
                # re-run picks it up. Never persist a partial result.
                print(f"  ✗ {stage} FAILED — will retry on next run: {e}")
                # If the *server* is gone (it has been OOM-killed before), stop rather
                # than churn through the remaining topics failing every call — that would
                # look like progress while doing nothing. Checkpoints are intact, so a
                # resume picks up exactly here.
                try:
                    llm.health()
                except llm.LlmError:
                    sys.exit("\nllama-server is unreachable — aborting so the run can be "
                             "resumed cleanly once it is back up.")
                continue
            ckpt.save(stage, tid, payload, wall_s=time.time() - t0)
            state[stage] = payload
            print(f"  ✓ {stage} ({time.time() - t0:.0f}s)")


def main(argv: list[str]) -> None:
    ap = argparse.ArgumentParser(prog="gen_content")
    ap.add_argument("--only", help="one topic id")
    ap.add_argument("--stage", action="append", choices=ckpt.STAGES,
                    help="run only this stage (repeatable)")
    ap.add_argument("--force", action="store_true", help="redo even if checkpointed")
    ap.add_argument("--dry-run", action="store_true", help="show what is left to do")
    args = ap.parse_args(argv)

    topics = load_topics()
    if args.only:
        topics = [t for t in topics if t["id"] == args.only]
        if not topics:
            sys.exit(f"no such topic: {args.only}")
    stages = args.stage or list(ckpt.STAGES)

    ids = [t["id"] for t in topics]
    print(f"{len(topics)} topics · stages: {', '.join(stages)}")
    for stage, (n, total) in ckpt.progress(ids).items():
        mark = "→" if stage in stages else " "
        print(f"  {mark} {stage:<12} {n}/{total} done")

    if args.dry_run:
        return
    llm.health()
    run(topics, stages, force=args.force)
    print("\nDone. Build the pack with:  uv run python -m src.build_content_db")


if __name__ == "__main__":
    main(sys.argv[1:])
