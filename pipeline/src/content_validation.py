"""Lightweight content-quality helpers shared by generation, packing, and tests."""

from __future__ import annotations

import re

_MATERIAL_CITATIONS = (
    ("excerpt", re.compile(r"\bexcerpt\s*\d+", re.IGNORECASE)),
    ("chapter", re.compile(r"\bch(?:apter)?\.?\s*\d+", re.IGNORECASE)),
    ("section", re.compile(r"\bsection\s*\d+", re.IGNORECASE)),
    ("figure", re.compile(r"\bfigure\s*\d+(?:\.\d+)?", re.IGNORECASE)),
    ("table", re.compile(r"\btable\s*\d+(?:\.\d+)?", re.IGNORECASE)),
)

_SCAFFOLDING_REFERENCES = (
    ("excerpt", re.compile(r"\b(?:ref(?:er)?\.?\s*)?excerpt\s*\d+\b", re.IGNORECASE)),
    ("prompt passage", re.compile(r"\b(?:the|this) passage\b", re.IGNORECASE)),
    ("text above", re.compile(r"\btext above\b", re.IGNORECASE)),
    ("given material", re.compile(r"\bgiven material\b", re.IGNORECASE)),
    ("according to prompt text", re.compile(r"\baccording to the text\b", re.IGNORECASE)),
    ("figure", re.compile(r"\bfigure\s*\d+(?:\.\d+)?", re.IGNORECASE)),
    ("table", re.compile(r"\btable\s*\d+(?:\.\d+)?", re.IGNORECASE)),
    ("cross-reference", re.compile(
        r"\b(?:as above|as described above|same apparatus|same activity|"
        r"the demonstration above|continuing from|as in the previous)\b",
        re.IGNORECASE,
    )),
)


def has_material_citation(material: str) -> bool:
    """Detect an actual textbook citation in a classroom materials entry.

    Word-boundary patterns avoid false positives for ordinary materials such as
    ``protein-rich foods``, ``catch tray``, ``pinch of salt``, and ``switch``.
    """

    return any(pattern.search(material) for _, pattern in _MATERIAL_CITATIONS)


def scaffolding_reference_issues(text: str) -> list[str]:
    """Return prompt-internal or unavailable-reference types found in user content."""

    return [name for name, pattern in _SCAFFOLDING_REFERENCES if pattern.search(text)]


# --------------------------------------------------------------------------- #
# Deterministic teacher-text sanitiser
#
# The generator sometimes leaks its own grounding scaffolding into teacher-visible
# lesson-plan prose: trailing "(Excerpt 7)" citation tags, and "Use Figure 5.6 from
# the textbook" instructions that point at a numbered book figure the plan does not
# embed. `scaffolding_reference_issues` flags these; this function *repairs* the exact
# leaked shapes deterministically so the surviving instruction is self-contained.
#
# It never merely strips the words "figure"/"table"/"excerpt": a book-figure
# instruction is rewritten to reference the diagram the teacher draws in class ("the
# board diagram" / "a diagram on the board"), and a citation tag is removed only when
# it is a parenthetical annotation whose deletion leaves a complete sentence. Anything
# it cannot make self-contained is left flagged, so the caller still excludes it.
# --------------------------------------------------------------------------- #

_NUM = r"\d+(?:\.\d+)*"
_FIG = (r"figures?\s*" + _NUM +
        r"(?:\s*(?:and|,|&)\s*(?:figures?\s*)?" + _NUM + r")*")
_TAB = (r"tables?\s*" + _NUM +
        r"(?:\s*(?:and|,|&)\s*(?:tables?\s*)?" + _NUM + r")*")
_EXC = r"(?:ref(?:er)?\.?\s*(?:to\s*)?)?excerpts?\s*\d+"

# Parenthetical citation tags: "(Excerpt 4)", "(Refer to Excerpt 3)", "(Ref. Excerpt 5)".
_PAREN_CITATION = re.compile(
    r"\s*\([^)]*\b(?:" + _EXC + r"|" + _FIG + r"|" + _TAB + r")\b[^)]*\)", re.IGNORECASE)
# "(Refer to previous lessons)" — a cross-lesson pointer with no in-plan referent.
_PAREN_PREVIOUS = re.compile(r"\s*\([^)]*\bprevious lessons?\b[^)]*\)", re.IGNORECASE)
# Book-figure/table noun phrases -> the diagram drawn in class. Order matters: the
# "the diagram/chart in Figure N" forms are rewritten before the bare "Figure N" form.
_DIAGRAM_IN_FIGURE = re.compile(r"\bthe diagram (?:shown |given )?in " + _FIG, re.IGNORECASE)
_CHART_IN_FIGURE = re.compile(r"\bthe chart (?:shown |given )?in " + _FIG, re.IGNORECASE)
_FIGURE_NP = re.compile(r"\b" + _FIG + r"(?:\s+from the textbook)?", re.IGNORECASE)
_TABLE_NP = re.compile(r"\b" + _TAB + r"(?:\s+from the textbook)?", re.IGNORECASE)
# "Mention the board diagram" reads oddly; the intent is to use it.
_MENTION_BOARD = re.compile(r"\bMention(?=\s+the board diagram)", re.IGNORECASE)
# Residual inline "... in Excerpt 1 ..." that was not parenthesised.
_INLINE_IN_EXCERPT = re.compile(r"\s+in\s+" + _EXC, re.IGNORECASE)
_TEXTBOOK_TAIL = re.compile(r"\s+from the textbook\b", re.IGNORECASE)
# A list line left holding only its marker ("4.", "-", "•") after a deletion.
_MARKER_ONLY = re.compile(r"[-*•]|\d+[.)]?")


def sanitize_plan_body(text: str) -> str:
    """Repair leaked scaffolding references in a lesson-plan body, deterministically.

    A no-op on any body `scaffolding_reference_issues` does not flag, so clean content
    is returned byte-for-byte unchanged. The result is idempotent.
    """

    if not scaffolding_reference_issues(text):
        return text

    lines: list[str] = []
    for line in text.split("\n"):
        line = _PAREN_CITATION.sub("", line)
        line = _PAREN_PREVIOUS.sub("", line)
        line = _DIAGRAM_IN_FIGURE.sub("a diagram on the board", line)
        line = _CHART_IN_FIGURE.sub("a chart on the board", line)
        line = _FIGURE_NP.sub("the board diagram", line)
        line = _TABLE_NP.sub("the board diagram", line)
        line = _MENTION_BOARD.sub("Use", line)
        line = _INLINE_IN_EXCERPT.sub("", line)
        line = _TEXTBOOK_TAIL.sub("", line)
        line = re.sub(r"\s+([.,;:])", r"\1", line)   # space left before punctuation
        line = re.sub(r"[ \t]{2,}", " ", line).rstrip()
        if _MARKER_ONLY.fullmatch(line.strip()):     # orphaned list marker -> drop
            continue
        lines.append(line)
    return "\n".join(lines).strip()
