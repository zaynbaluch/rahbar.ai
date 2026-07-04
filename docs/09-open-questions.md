# 09 — Open Questions

Running list of things to confirm. Resolved items keep their answer for the record.

## Resolved
- **UI/content language?** → **English throughout.**
- **Target device tier?** → **Budget Android, 2–4 GB RAM.**
- **App framework?** → **Flutter, Android-only.**
- **First prototype?** → **On-device generation (SLM + RAG).**
- **MVP subject/class?** → **General Science, Class 6 only.**
- **Timeline?** → **3 weeks full-time; aim state-of-the-art.**
- **Textbook available & type?** → **PCTB "Web Version" Class 6, 153 pp, scanned + watermarked** (OCR + cleanup needed).
- **Platform longevity?** → **Android-only for the foreseeable future.**
- **Lesson-plan depth?** → **Full, structured, pedagogy-rich** (5E schema, [ADR-006](decisions/ADR-006-lesson-plan-schema.md)).
- **MCQ defaults?** → **10 questions, mixed difficulty**, printable (PDF), **OMR-compatible**. Grading looks up the answer key by **test ID — no SLM** ([ADR-007](decisions/ADR-007-assessment-and-omr.md)).
- **Lesson duration?** → **50 minutes, one topic per period**; suggest splitting into parts if too long.
- **Demo wow-factor?** → **instant speed, PDF export, OMR checking, intuitive UI.**

## Open — I'll resolve during the build (will confirm as I go)
4. **SLO source for Class 6 General Science** — is there an official digital SLO list, or do
   we derive SLOs from chapter objectives + Key Points? (Affects chunk anchoring.)
5. **Generation model final pick** — resolved by the Week-1 on-device spike
   ([ADR-003](decisions/ADR-003-generation-model.md)).
6. **VLM for diagram captioning** — which model/service for the build-time captioning step
   (local vs API), given it runs off-device.
7. **Licensing/attribution** for using PCTB textbook content in a product — confirm
   permitted use for the launchpad/MVP context.
