# Pedagogy Research

Background research so Rahbar AI's lesson plans are pedagogically credible. The developer is
not an educator; this doc records the *why* behind [ADR-006](decisions/ADR-006-lesson-plan-schema.md).
**Caveat:** these are secondary web sources; before the demo, a practicing teacher should
review a few generated plans.

## Lesson-plan frameworks

### 5E instructional model (our spine)
Developed by the **Biological Sciences Curriculum Study (BSCS)** in the 1980s, explicitly for
science. Five phases:

- **Engage** — capture attention, surface prior knowledge, create curiosity.
- **Explore** — students investigate hands-on before formal explanation.
- **Explain** — teacher formalizes concepts and vocabulary.
- **Elaborate** — apply/extend to new contexts.
- **Evaluate** — assess understanding (formative + summative).

Inquiry-based and constructivist — students build knowledge rather than receive it. It maps
cleanly onto the PCTB book's own **Inquiry → Activity → Key Points** rhythm, which is why we
adopt it as the backbone.

### Madeline Hunter model (direct instruction)
Seven steps: anticipatory set, objective & purpose, input, modelling, guided practice,
independent practice, closure. Strong for **procedural/skills** topics where "get it right
the first time" matters. We borrow its **explicit objectives, modelling, and closure** ideas
inside the 5E structure.

### Backward Design (UbD)
Design method: start from desired outcomes and assessment evidence, then plan activities. We
apply it by making lesson plans **SLO-first** — objectives and the final assessment are
defined before activities.

> Consensus in the sources: no framework is universally best; match it to learners and
> content. Hence 5E spine + Backward-Design planning + Hunter's explicit-instruction touches.

## Evidence-based components we include

- **Retrieval practice (revision starter)** — a short recall quiz at the start activates
  prior knowledge and strengthens memory; effective questioning as a starter establishes
  current understanding. → schema step 4.
- **Bloom's taxonomy** — objectives and questions tagged from *remember/understand* up to
  *analyze/evaluate/create* add cognitive rigor and make learning measurable. → steps 3, 8.
- **Socratic questioning** — layered questioning (clarify → assumptions → evidence →
  implications) reveals and deepens understanding. → steps 5, 8.
- **Formative assessment / exit tickets / hinge questions** — quick end-of-lesson checks tell
  the teacher whether the objective landed and what to reteach. → step 10.
- **Low-cost, locally-available practical work** — in resource-poor, large classrooms,
  hands-on activities with everyday materials **measurably raise achievement** (high effect
  size) and connect science to students' lives. → steps 2, 6.

## Context constraints that shape the plans

- **Large, multi-grade classes (60–70 students):** activities must scale (group/whole-class),
  need minimal materials, and include management notes. → steps 6, 11.
- **English-medium, Class 6 General Science, SNC/PCTB:** content and vocabulary anchored to
  the official textbook and its SLOs.
- **Teacher time is scarce:** the plan must be usable as-is, editable, and printable — reduce
  prep, don't add homework for the teacher.

## Sources

- 5E model & comparisons: <https://www.schoolgpt.app/resources/lesson-plan-formats> · <https://tevello.com/blogs/content-strategy/lesson-plan-outline-sample-proven-frameworks-to-engage-students>
- Madeline Hunter: <https://thesecondprinciple.com/essential-teaching-skills/models-of-teaching/madeline-hunter-lesson-plan-model/> · <https://blog.ailessonplan.com/post/madeline-hunter-lesson-plan>
- Backward Design: <https://study.com/academy/lesson/backward-design-lesson-plan-example.html>
- Lesson-plan components & formative assessment: <https://teachers-blog.com/lesson-plan-components/> · <https://www.cliffsnotes.com/study-notes/21912117>
- Bloom's taxonomy & questioning: <https://www.turnitin.com/blog/blooms-taxonomy-how-do-you-use-blooms-taxonomy-in-the-classroom> · <https://www.ukessays.com/essays/teaching/effective-questioning-and-blooms-taxonomy-in-the-classroom.php>
- Low-cost science practical work: <https://link.springer.com/chapter/10.1007/978-3-032-13788-3_19> · <https://www.sciencedirect.com/science/article/abs/pii/S174977282030049X> · <https://www.educationworld.com/teachers/stem-budget-low-cost-experiments-make-science-come-alive>
