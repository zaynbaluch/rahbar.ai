# ADR-006 — Lesson-plan schema: 5E spine + Bloom + retrieval/Socratic/exit-ticket

**Status:** Accepted · **Date:** 2026-07-04

## Context

The developer is not an educator and asked for a **full, structured, pedagogy-rich**
lesson plan — explicitly wanting previous-revision questions, Socratic questions, delivery,
in-class activities, props, "and everything a good improved teaching experience could have."
So the schema must be **research-backed**, not invented, and it must be machine-generable by
a small on-device model from retrieved curriculum chunks.

## Options considered

| Framework | Nature | Fit for us |
|---|---|---|
| **5E (Engage–Explore–Explain–Elaborate–Evaluate)** | Inquiry-based, built by the Biological Sciences Curriculum Study **for science** | **Best** — maps 1:1 onto the textbook's Inquiry → Activity → Key-Points structure |
| Madeline Hunter (7 steps) | Direct-instruction | Good for procedural topics; less inquiry-driven |
| Backward Design (UbD) | Outcomes-first design method | Great *design* lens; we bake it in via SLO-first objectives |

No single model is universally best; we take **5E as the spine** and fold in Backward-Design
(SLO-first) plus specific evidence-based components the user named.

## Decision — the schema

A generated lesson plan is a structured object with these sections:

1. **Header** — class, subject, chapter/topic, **SNC SLOs covered**, **duration (one
   50-minute period, one topic per period)**, class-size note. If the topic can't
   realistically fit one 50-min period, the plan must **suggest splitting it into parts
   (Part 1 / Part 2)** with a natural break point, rather than overrun.
2. **Materials / props** — low-cost, **locally available** items (evidence: low-cost
   practical work measurably raises achievement in resource-poor, large classrooms).
3. **Objectives** — SLO-aligned, tagged to **Bloom's taxonomy** levels with action verbs.
4. **Revision starter** — 3–5 quick **retrieval-practice** recall questions on the prior
   lesson (the user's "previous revision questions"; starters activate prior knowledge).
5. **Engage (hook)** — real-life connection + an opening Socratic question.
6. **Explore** — in-class **activity**, preferring the book's own Activity boxes, with
   steps, grouping, and **large-class (60–70) management** tips.
7. **Explain (delivery)** — teacher explanation, key concepts, how to use the figure/diagram.
8. **Socratic question set** — layered (clarify → assumptions → evidence → implications),
   laddered across Bloom levels.
9. **Elaborate** — extension / real-world application.
10. **Evaluate** — **exit-ticket / hinge questions** + auto-generated **MCQs** (reuses the
    MCQ generator) + the book's Key Points as a recap.
11. **Differentiation & multi-grade notes** — for the multi-grade reality in the problem statement.
12. **Homework + next-lesson bridge.**

The **MCQ generator plugs into step 10**, so lesson plans and standalone tests share one
generation pipeline and prompt library.

## Consequences

- Prompt templates ([`../../prompts/`](../../prompts/)) encode this schema and instruct the
  model to fill each section **only** from retrieved chunks (+ flag when the book lacks
  material for a section).
- Block-typed chunks ([ADR-005](ADR-005-pdf-preprocessing.md)) let retrieval prefer
  `activity` blocks for Explore, `inquiry` blocks for Socratic/Engage, `key_points` for recap.
- Output is stored as structured JSON so the UI can render, and the teacher can edit, each
  section independently.
- Each 5E phase carries a **suggested minute allocation** summing to ~50 (e.g. Engage 5 ·
  Revision 5 · Explore 12 · Explain 12 · Elaborate 8 · Evaluate/exit-ticket 8), so the
  teacher can pace the period and see immediately if a topic needs splitting.
- MCQ sub-generation for the Evaluate phase follows [ADR-007](ADR-007-assessment-and-omr.md)
  (10 questions, mixed difficulty, printable/OMR-compatible).
- The schema is validated with real pedagogy sources (see [`../pedagogy-research.md`](../pedagogy-research.md));
  ideally reviewed by a practicing teacher before the demo.

## Sources

- 5E vs Madeline Hunter vs Backward Design: <https://www.schoolgpt.app/resources/lesson-plan-formats> · <https://thesecondprinciple.com/essential-teaching-skills/models-of-teaching/madeline-hunter-lesson-plan-model/>
- Lesson-plan components / formats: <https://teachers.institute/managing-teaching-learning/lesson-planning-techniques-formats-best-practices/> · <https://teachers-blog.com/lesson-plan-components/>
- Bloom's taxonomy + questioning + exit tickets: <https://www.turnitin.com/blog/blooms-taxonomy-how-do-you-use-blooms-taxonomy-in-the-classroom> · <https://www.ukessays.com/essays/teaching/effective-questioning-and-blooms-taxonomy-in-the-classroom.php>
- Low-cost science practical work raises achievement: <https://link.springer.com/chapter/10.1007/978-3-032-13788-3_19> · <https://jriiejournal.com/wp-content/uploads/2023/02/JRIIE-7-1-006-.pdf>
