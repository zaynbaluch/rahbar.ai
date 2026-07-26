# Bayaz AI - App-Only MVP

Bayaz AI is an offline-first Flutter/Android teacher application for low-connectivity classrooms. This repository is intentionally limited to the app and the tooling required to build and verify its bundled curriculum content.

## Current app scope

- Class 6 General Science coursework included in the app.
- Class, subject, and topic navigation with recently accessed topics.
- Structured lesson-plan and MCQ presentation.
- Optional custom lesson and MCQ generation using separately installed local models.
- Compact offline clarification chat using only relevant context.
- PDF export, local library, and on-device OMR grading with teacher review for uncertain answers.
- Three-step onboarding and simple optional model management.
- Branding, splash-screen, logo, and home-card layout fixes.

The app does not initialize a backend, cloud analytics, background synchronization, school administration, licensing, payments, or a download website. Those areas are documented only as research questions under `research/`.

## Repository layout

| Path | Purpose |
|---|---|
| `app/` | Flutter Android application. |
| `pipeline/` | Curriculum processing, generation, validation, and database packaging. |
| `prompts/` | Versioned generation prompt source. |
| `eval/` | Retrieval and generation evaluation utilities. |
| `scripts/` | Toolchain, native runtime, content-build, and validation scripts. |
| `docs/` | Current app architecture, decisions, content quality, branding, setup, and OMR validation. |
| `research/` | Deferred systems described as research only; no runnable external service is included. |

## First build

```bash
bash scripts/setup-llama.sh
bash scripts/check-environment.sh
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The source package intentionally does not include `app/pubspec.lock`, because the dependency set was reduced without a Flutter SDK in the packaging environment. Generate it with the pinned Flutter version and commit the resulting lockfile in the real Git repository.

See `SCOPE.md` before implementing backlog items and `TRANSFER_TO_GITHUB_REPO.md` before copying this delivery into an existing repository.

## Existing repository migration

For the current `D:\GITHUB\rahbar.ai` checkout, read `MIGRATION_DECISIONS.md` before `TRANSFER_TO_GITHUB_REPO.md`. It records the verified `ui-revamp` base, preservation rules for target-only files, adaptive feature commits, and dependency-tracking rules.
