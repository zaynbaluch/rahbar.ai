#!/usr/bin/env python3
"""Structural grade of bake-off MCQ/lesson outputs. Correctness of answers still
needs a human eye, but this flags the mechanical failures that break the app:
missing questions, missing ANSWER lines, missing difficulty tags, and
ANSWER-vs-KEY internal contradictions.
"""
import pathlib, re, json

OUT = pathlib.Path("/tmp/claude-1000/-mnt-Personal-Atelier-rahbar-ai/46278caa-3a73-41b1-bf8e-8814a56f0d51/scratchpad/bakeoff_out")
HEADER = re.compile(r'^\s*Q(\d+)\s*(?:\[([^\]]+)\])?', re.M)
ANSWER = re.compile(r'^\s*ANSWER\s*[:=]?\s*\(?\s*([A-D])', re.M | re.I)
OPTION = re.compile(r'^\s*([A-D])[).]\s+\S', re.M)
KEYLINE = re.compile(r'^\s*KEY\s*[:=]\s*(.+)$', re.M | re.I)
KEYPAIR = re.compile(r'(\d+)\s*[=:]\s*([A-D])', re.I)


def strip_prompt(text):
    # llama-cli echoes the prompt; keep only from the first fenced answer or Q1.
    m = re.search(r'^\s*Q1\b', text, re.M)
    return text[m.start():] if m else text


def grade_mcq(text):
    body = strip_prompt(text)
    qnums = [int(m.group(1)) for m in HEADER.finditer(body)]
    difftags = [m.group(2) for m in HEADER.finditer(body) if m.group(2)]
    answers = ANSWER.findall(body)
    # per-question ANSWER map by walking blocks
    per_q = {}
    blocks = re.split(r'^\s*Q(\d+)', body, flags=re.M)
    # blocks: [pre, '1', block1, '2', block2, ...]
    for i in range(1, len(blocks) - 1, 2):
        n = int(blocks[i]); blk = blocks[i + 1]
        a = ANSWER.search(blk)
        per_q[n] = a.group(1).upper() if a else None
    keym = KEYLINE.search(body)
    keymap = {}
    if keym:
        for m in KEYPAIR.finditer(keym.group(1)):
            keymap[int(m.group(1))] = m.group(2).upper()
    # ANSWER vs KEY contradictions (only where both exist)
    contra = [n for n in per_q if n in keymap and per_q[n] and per_q[n] != keymap[n]]
    return {
        "n_questions": len(set(qnums)),
        "n_with_answer": sum(1 for v in per_q.values() if v),
        "difficulty_tags": len(difftags),
        "key_entries": len(keymap),
        "answer_key_contradictions": len(contra),
    }


def grade_lesson(text):
    body = strip_prompt(text) if re.search(r'^\s*Q1\b', text, re.M) else text
    # crude: count 5E section keywords present
    fivee = [w for w in ("Engage", "Explore", "Explain", "Elaborate", "Evaluate")
             if re.search(w, body, re.I)]
    return {"chars": len(body), "fivee_sections": len(fivee), "fivee": fivee}


def main():
    rows = []
    for f in sorted(OUT.glob("*.txt")):
        name = f.stem  # slug__model
        slug, _, model = name.rpartition("__")
        text = f.read_text(errors="replace")
        kind = "mcq" if slug.startswith("mcq__") else "lesson"
        g = grade_mcq(text) if kind == "mcq" else grade_lesson(text)
        rows.append({"slug": slug, "model": model, "kind": kind, **g})
    print(json.dumps(rows, indent=2))
    # summary by model for mcq
    print("\n=== MCQ summary by model ===")
    by = {}
    for r in rows:
        if r["kind"] != "mcq":
            continue
        by.setdefault(r["model"], []).append(r)
    for model, rs in sorted(by.items()):
        nq = sum(r["n_questions"] for r in rs) / len(rs)
        na = sum(r["n_with_answer"] for r in rs) / len(rs)
        dt = sum(r["difficulty_tags"] for r in rs) / len(rs)
        print(f"{model:12} avg_questions={nq:.1f}/10  avg_with_answer={na:.1f}  avg_difftags={dt:.1f}/10")


if __name__ == "__main__":
    main()
