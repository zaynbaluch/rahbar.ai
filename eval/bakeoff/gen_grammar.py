#!/usr/bin/env python3
"""Generate a GBNF grammar that forces the exact MCQ schema the app parses:
10 blocks of `Qn [difficulty]\\n<stem>\\nA)..D)\\nANSWER: X\\n\\n`, then a KEY line.
This makes schema-adherence a property of decoding, not of the model — so a fast
but less-disciplined model (LFM2) still emits parseable, OMR-ready output.
"""
import pathlib

N = 10
lines = []
root_syms = " ".join(f"block{i}" for i in range(1, N + 1)) + " key"
lines.append(f"root ::= {root_syms}")
for i in range(1, N + 1):
    lines.append(
        f'block{i} ::= "Q{i} [" diff "]\\n" text "\\n" '
        f'"A) " text "\\n" "B) " text "\\n" "C) " text "\\n" "D) " text "\\n" '
        f'"ANSWER: " letter "\\n\\n"'
    )
key_pairs = " ".join(f'" {i}=" letter' for i in range(1, N + 1))
lines.append(f'key ::= "KEY:" {key_pairs} "\\n"')
lines.append('diff ::= "easy" | "medium" | "hard"')
lines.append('letter ::= "A" | "B" | "C" | "D"')
# A line of visible text: at least one non-newline char, bounded so a runaway
# generation can't stall. 1..200 chars.
lines.append('text ::= char char{0,199}')
lines.append('char ::= [^\\n]')

out = pathlib.Path(__file__).parent / "mcq.gbnf"
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(out.read_text())
