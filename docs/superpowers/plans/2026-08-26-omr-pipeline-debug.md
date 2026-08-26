# OMR Pipeline and Debugging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a staged, diagnostic OMR pipeline that rectifies the answer region, uses local/per-sheet calibration, classifies conservatively, and surfaces copyable debugging evidence in the grading UI.

**Architecture:** Keep `OmrGrader.grade` as the public compatibility entry point while moving registration, rectification, quality measurement, bubble analysis, and diagnostics into focused files. The pipeline uses the existing `image` package and `ProjectiveMapper`; no OpenCV or ML dependency is added.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, `image` 4.9.x, existing PDF/OMR geometry and isolate worker.

**Spec:** `docs/superpowers/specs/2026-08-26-omr-pipeline-debug-design.md`

## Global Constraints

- Branch/worktree: `omr_debug`; do not implement on `ui_v2`.
- Preserve the current four-square paper format and 1-15 question `OmrTemplate` geometry.
- Preserve teacher confirmation for uncertain rows and all existing local gradebook behavior.
- Keep processing offline and isolate-safe.
- Add no OpenCV, ML, backend, OCR, or coded-marker dependency.
- Diagnostics must be copyable from the app on both successful scans and registration failures.
- Use test-first changes and keep existing OMR entry points compatible.

---

### Task 1: Diagnostic and decision domain

**Files:**
- Create: `app/lib/features/omr/omr_diagnostics.dart`
- Modify: `app/lib/features/omr/omr_grader.dart`
- Test: `app/test/omr_diagnostics_test.dart`

**Interfaces:**
- Produces `OmrFailureCode`, `OmrScanStatus`, `OmrBubbleDiagnostic`, `OmrRowDiagnostic`, `OmrDiagnostics.toJson/fromJson/toReport`.
- Extends `OmrQuestion` with a serializable decision reason/status while keeping old JSON readable.
- Extends `OmrResult` with optional diagnostics and bases `needsReview` on explicit uncertainty plus teacher review.

- [ ] Write failing serialization/report/backward-compatibility tests.
- [ ] Run the focused test and confirm RED because diagnostic types do not exist.
- [ ] Implement the minimum domain types and compatibility defaults.
- [ ] Run the focused test and existing grading-flow tests; confirm GREEN.
- [ ] Commit diagnostic domain.

### Task 2: Quality measurement and robust fiducial registration

**Files:**
- Create: `app/lib/features/omr/omr_image_quality.dart`
- Create: `app/lib/features/omr/omr_registration.dart`
- Test: `app/test/omr_registration_test.dart`

**Interfaces:**
- `OmrImageQuality.measure(img.Image gray)` returns dimensions/exposure/clipping/blur metrics and warnings.
- `OmrRegistration.detect(img.Image gray, OmrLayout layout)` returns candidate count, chosen TL/TR/BR/BL centers, score, or a typed failure reason.

- [ ] Write failing tests for valid square markers, dark non-square corner clutter, perspective markers, and tiny-image rejection.
- [ ] Run focused tests and confirm RED.
- [ ] Implement adaptive-mask connected components, candidate scoring, quadrant grouping, and geometry scoring.
- [ ] Run focused tests plus existing `omr_grader_test.dart`; confirm GREEN.
- [ ] Commit registration stage.

### Task 3: Canonical rectification

**Files:**
- Create: `app/lib/features/omr/omr_rectifier.dart`
- Test: `app/test/omr_rectifier_test.dart`

**Interfaces:**
- `OmrRectifier.rectify(gray, fiducials, layout)` returns a fixed grayscale canonical image whose unit-square coordinates align with `OmrLayout.norm`.

- [ ] Write a failing test with a perspective quadrilateral containing known interior points.
- [ ] Run focused test and confirm RED.
- [ ] Implement inverse destination sampling through `ProjectiveMapper` with bilinear luminance interpolation.
- [ ] Run rectifier and existing perspective grader tests; confirm GREEN.
- [ ] Commit rectification stage.

### Task 4: Bubble observation, sheet calibration, and conservative row classification

**Files:**
- Create: `app/lib/features/omr/omr_bubble_analysis.dart`
- Test: `app/test/omr_bubble_analysis_test.dart`

**Interfaces:**
- `OmrBubbleSampler.sample(canonical, layout, q, option)` returns interior/background/contrast/density/composite score.
- `OmrSheetCalibration.fromObservations(...)` returns blank baseline, MAD, and clamped mark threshold.
- `OmrRowClassifier.classify(...)` returns marked/blank/ambiguous, confidence, fill, and a reason.

- [ ] Write failing tests for clean fill, blank row, local shadow, faint mark, and double mark.
- [ ] Confirm RED.
- [ ] Implement local annulus sampling, robust blank baseline/MAD, and conservative row classification.
- [ ] Confirm focused GREEN.
- [ ] Commit bubble-analysis stage.

### Task 5: Pipeline orchestration and compatibility grader

**Files:**
- Create: `app/lib/features/omr/omr_pipeline.dart`
- Modify: `app/lib/features/omr/omr_grader.dart`
- Modify: `app/lib/features/omr/omr_image_processor.dart`
- Test: `app/test/omr_pipeline_test.dart`
- Test: `app/test/omr_grader_test.dart`
- Test: `app/test/features/omr/omr_15_question_test.dart`

**Interfaces:**
- `OmrPipeline.scan(image, key)` orchestrates quality -> registration -> rectification -> bubble analysis -> calibration -> row decisions -> diagnostics.
- `OmrGrader.grade` delegates to `OmrPipeline.scan`.
- Isolate serialization carries diagnostics without changing `OmrImageProcessor.process` call sites.

- [ ] Write failing pipeline tests covering clean, perspective, shadowed, blank, ambiguous, registration failure, and 15-question sheets.
- [ ] Confirm RED against the old grader.
- [ ] Implement pipeline orchestration and delegate the compatibility entry point.
- [ ] Run the full OMR test subset and confirm GREEN.
- [ ] Commit pipeline integration.

### Task 6: Debug-first grading UI

**Files:**
- Modify: `app/lib/features/omr/grading_screen.dart`
- Test: `app/test/features/omr/grade_papers_flow_test.dart`

**Interfaces:**
- Successful and failed-readable scans expose `OmrDiagnostics.toReport()` through a `Scan diagnostics` expansion card.
- A copy action writes the complete report to the clipboard and confirms with a SnackBar.
- Registration failure keeps diagnostics rather than collapsing immediately to an opaque generic error.

- [ ] Write failing widget tests for visible diagnostics, copy action, and registration-failure report retention.
- [ ] Confirm RED.
- [ ] Implement diagnostic state capture and the expandable/copyable card.
- [ ] Run focused widget tests and confirm GREEN.
- [ ] Commit debug UI.

### Task 7: Release evidence and final verification

**Files:**
- Modify: `docs/omr/OMR_VALIDATION_PLAN.md`

**Interfaces:**
- Document the new staged pipeline and explicitly retain the five image-generated sheets as manual Level-A smoke tests before real A05 photos.

- [ ] Update validation documentation with diagnostic fields and manual test recording format.
- [ ] Run `flutter analyze`.
- [ ] Run full `flutter test --concurrency=4` and require zero failures.
- [ ] Build `flutter build apk --debug --target-platform android-arm64`.
- [ ] Inspect `git status`, commit documentation/final cleanups, and record APK hash.
