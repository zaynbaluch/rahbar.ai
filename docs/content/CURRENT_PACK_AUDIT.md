# Current curriculum pack audit

Pack: `app/assets/content/content_pack.db`

- SQLite integrity: **ok**
- Topics: **88**
- Verified MCQs: **1447**
- Duplicate normalized stem groups: **62** (138 items)

## Answer positions in the source bank

| Position | Count | Percentage |
|---|---:|---:|
| A | 196 | 13.55% |
| B | 732 | 50.59% |
| C | 441 | 30.48% |
| D | 78 | 5.39% |

The application now repositions correct answers into balanced per-paper targets when option wording is position-independent. Source-bank bias must still be reduced during the next content regeneration and human review.

## Thin question banks

- Particles in Material Objects: 5 verified items

## Duplicate section numbers

- Chapter 1 / 1.3.1: Organs and Organ Systems in Plants; Organs and Organ Systems in Human Body
- Chapter 8 / 8.4: Law of Conservation of Energy; Sources of Energy
- Chapter 9 / 9.2: Current Electricity; Electromagnets
- Chapter 11 / 11.3: Preparation of Cheese at Home; How to Make a Solar Oven and Assemble an Electric Bell

## Lesson-plan reference warnings

- Variants with internal excerpt, figure, table, or cross-variant references: **23**
- `ch01-1_2_1-2b0a-explore-2`: figure
- `ch01-1_2_2-2791-explain-0`: figure
- `ch03-3_2_2-cd0e-revision_starter-0`: excerpt
- `ch03-3_2_2-cd0e-revision_starter-1`: excerpt
- `ch03-3_2_2-cd0e-engage-1`: excerpt
- `ch03-3_2_2-cd0e-explain-0`: excerpt, table
- `ch03-3_2_2-cd0e-elaborate-0`: excerpt
- `ch03-3_2_2-cd0e-elaborate-1`: excerpt
- `ch03-3_2_2-cd0e-evaluate-0`: excerpt
- `ch03-3_2_2-cd0e-evaluate-1`: excerpt
- `ch03-3_2_2-cd0e-homework-0`: excerpt
- `ch03-3_2_2-cd0e-homework-1`: excerpt

## Release blockers

- Lesson-plan variants still expose internal excerpt references; regenerate the pack from verified checkpoints before release

## Required release review

Automated checks do not establish educational correctness. A subject teacher must review representative questions, all answer keys, rationales, lesson instructions, materials, references, and culturally/contextually sensitive content before release.
