"""Dump faithful grounded (system, user) prompts to JSON for the model bake-off.

Uses the exact same retrieval + template assembly as the app (bge-small retrieval,
k=6, char budget) so a locally-run model sees precisely what the phone would. Writes
one JSON file per (kind, topic) into the given output dir, plus an index.

Run: uv run python -m src.dump_prompts <out_dir>
"""

from __future__ import annotations

import json
import pathlib
import sys

from .rag_prompt import TEMPLATES, build_context, derive_slos, retrieve

# The Class-6 General Science topics we bake off on. Mix of chapters so retrieval
# and schema-adherence are exercised across the corpus, not one lucky topic.
TOPICS = [
    "the human digestive system",
    "states of matter",
    "photosynthesis in plants",
    "force and motion",
]


def assemble_roles(kind: str, topic: str, k: int = 6) -> tuple[str, str]:
    template = TEMPLATES[kind].read_text(encoding="utf-8")
    hits = retrieve(topic, k=k)
    filled = (
        template.replace("{{topic}}", topic)
        .replace("{{slos}}", derive_slos(hits))
        .replace("{{context}}", build_context(hits))
    )
    _, _, rest = filled.partition("## SYSTEM")
    system, _, user = rest.partition("## USER")
    return system.strip(), user.strip()


def main(argv: list[str]) -> None:
    out = pathlib.Path(argv[0]) if argv else pathlib.Path("prompts_out")
    out.mkdir(parents=True, exist_ok=True)
    index = []
    for kind in ("mcq", "lesson"):
        for topic in TOPICS:
            system, user = assemble_roles(kind, topic)
            slug = f"{kind}__{topic.replace(' ', '_')}"
            rec = {"kind": kind, "topic": topic, "system": system, "user": user}
            (out / f"{slug}.json").write_text(json.dumps(rec, indent=2), encoding="utf-8")
            index.append(slug)
            print(f"wrote {slug}  (system {len(system)}c, user {len(user)}c)")
    (out / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:])
