"""Emit a model-ready, chat-formatted grounded prompt for a topic.

Retrieves curriculum context from curriculum.db, fills the lesson/MCQ template,
splits it into system + user, and wraps it in the Llama 3.2 chat template so it
can be fed to `llama-cli -no-cnv` for a quality check of grounded generation.

Run: uv run python -m src.make_test_prompt mcq "the human digestive system"
"""

from __future__ import annotations

import sys

from .rag_prompt import TEMPLATES, build_context, derive_slos, retrieve


def build(kind: str, topic: str, k: int = 6) -> str:
    template = TEMPLATES[kind].read_text(encoding="utf-8")
    hits = retrieve(topic, k=k)
    filled = (
        template.replace("{{topic}}", topic)
        .replace("{{slos}}", derive_slos(hits))
        .replace("{{context}}", build_context(hits))
    )
    # Templates are "## SYSTEM ... ## USER ..." — split into the two roles.
    _, _, rest = filled.partition("## SYSTEM")
    system, _, user = rest.partition("## USER")
    system, user = system.strip(), user.strip()

    # Llama 3.2 chat template.
    return (
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
        f"{system}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n"
        f"{user}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
    )


def main(argv: list[str]) -> None:
    if len(argv) < 2 or argv[0] not in TEMPLATES:
        print("usage: python -m src.make_test_prompt <lesson|mcq> \"<topic>\"",
              file=sys.stderr)
        return
    sys.stdout.write(build(argv[0], " ".join(argv[1:])))


if __name__ == "__main__":
    main(sys.argv[1:])
