# Rahbar AI — Documentation Index

Read in order; ADRs are the "why" behind each choice.

## Orientation
- [`00-overview.md`](00-overview.md) — problem, MVP scope, goals, glossary.
- [`01-architecture.md`](01-architecture.md) — build-time vs on-device split; components; data model.

## Decision records (ADRs)
- [`decisions/ADR-001-app-framework.md`](decisions/ADR-001-app-framework.md) — Flutter, Android-only.
- [`decisions/ADR-002-on-device-inference.md`](decisions/ADR-002-on-device-inference.md) — flutter_gemma/LiteRT (llama.cpp fallback).
- [`decisions/ADR-003-generation-model.md`](decisions/ADR-003-generation-model.md) — model shortlist → spike → pick.
- [`decisions/ADR-004-rag-stack.md`](decisions/ADR-004-rag-stack.md) — EmbeddingGemma + sqlite-vec, prebuilt corpus.
- [`decisions/ADR-005-pdf-preprocessing.md`](decisions/ADR-005-pdf-preprocessing.md) — watermark → Docling OCR → VLM caption → SLO chunk.
- [`decisions/ADR-006-lesson-plan-schema.md`](decisions/ADR-006-lesson-plan-schema.md) — 5E + Bloom + retrieval/Socratic/exit-ticket; 50-min period.
- [`decisions/ADR-007-assessment-and-omr.md`](decisions/ADR-007-assessment-and-omr.md) — 10-MCQ tests, PDF export, OMR grading by test ID (no SLM).

## Research & planning
- [`pedagogy-research.md`](pedagogy-research.md) — lesson-plan frameworks & evidence (cited).
- [`06-rag-quality-plan.md`](06-rag-quality-plan.md) — grounding, eval harness, risks.
- [`07-3week-plan.md`](07-3week-plan.md) — milestone breakdown + risk register.
- [`08-deferred-omr-backend.md`](08-deferred-omr-backend.md) — later-phase design.
- [`09-open-questions.md`](09-open-questions.md) — resolved + open questions.
