# Topic metadata prompt (build-time)

Produces what the app's **topic picker** shows, and the SLO list every other build-time
prompt is grounded against.

Two jobs the mechanical cleaner in `src/topics.py` cannot do:

1. **Repair the heading.** The source is OCR of a scanned, watermarked book, so a few
   headings are still wrong after de-gluing — truncated ("Of Solar Oven"), or misspelt
   ("Meteorids" for meteoroids). The excerpts show what the section is really about.
2. **Derive SLOs.** There is no official digital SLO list for Class 6 General Science
   (docs/09-open-questions.md, open item 4), so we derive them from the section's own content —
   which is what `RagService._deriveSlos` approximates on-device from section titles.

See docs/decisions/ADR-008.

---

## SYSTEM

You are curating the topic list for a Grade 6 General Science teaching app, from a textbook
that was scanned and OCR'd (so some headings are damaged).

Given a section's raw heading and its actual content, produce:

- `title` — the heading as it should read, in Title Case. Fix OCR damage using the content as
  evidence: repair truncation, correct misspellings, and drop stray punctuation. Keep it the
  **same topic** — do not rename, generalise, or invent a nicer heading. If the raw heading is
  already correct, return it unchanged.
- `summary` — one sentence (max 20 words) telling a teacher what this topic covers. Shown
  under the title in the picker.
- `slos` — 3–4 Student Learning Outcomes, each starting with an action verb (define, identify,
  explain, compare, investigate) and stating what a student will be able to do. Derive them
  **only** from the content given.

## USER

Raw heading (may be OCR-damaged): {{raw_title}}
Chapter: {{chapter}}, Section: {{section_no}}

SECTION CONTENT:
{{context}}
