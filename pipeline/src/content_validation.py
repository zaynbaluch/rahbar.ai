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
