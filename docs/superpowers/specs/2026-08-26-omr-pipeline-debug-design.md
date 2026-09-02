# OMR Pipeline and Debugging Design

## Goal

Replace Bayaz's monolithic OMR heuristic with an explicit deterministic computer-vision pipeline that is easier to validate, safer around uncertain marks, and diagnostic enough that a failed manual scan can be debugged from a copied report instead of reproducing the whole exploration.

## Scope

This work stays fully offline and keeps the current Bayaz printed paper format: four solid square fiducials, known 5/10/15-question bubble coordinates, and teacher review before saving uncertain answers. It does not add ML, circle detection, coded markers, a backend, or OCR. The existing `OmrGrader.grade(image, key)` entry point remains available so current callers do not need a second grading architecture.

## Pipeline

1. **Decode and orient** in `OmrImageProcessor`, retaining the existing EXIF bake and 2000px cap.
2. **Capture quality** measures image dimensions, mean exposure, clipped dark/light fractions, and a simple Laplacian-variance blur score. Quality produces warnings and diagnostics; only unusably tiny images are rejected at this stage.
3. **Fiducial registration** creates an adaptive dark mask, extracts connected components, scores square/solid candidates, groups candidates by expected quadrant, and chooses the best geometrically consistent TL/TR/BR/BL set. The four markers must be similar in scale and form a plausible convex quadrilateral.
4. **Canonical rectification** uses the selected marker centers and the existing projective homography to resample the photographed answer region into a fixed canonical image. Later stages therefore operate in stable pixel coordinates.
5. **Local photometric normalization** is performed during bubble measurement: the bubble interior is compared with a local paper annulus so shadows and exposure changes cancel rather than relying on absolute grayscale alone.
6. **Bubble measurement** samples every known bubble location from `OmrTemplate`; no Hough/circle detection is introduced. Each bubble produces interior darkness, local background darkness, local contrast, dark-pixel density, and a composite mark score.
7. **Sheet calibration** uses the lower-score majority of all bubbles to estimate the blank distribution and derive a per-sheet mark threshold. Fixed conservative clamps prevent a pathological sheet from calibrating itself into confident answers.
8. **Row classification** emits marked A/B/C/D, blank, or ambiguous. Two competitive marks must become ambiguous instead of selecting the darkest one. Confidence is derived from mark strength and winner margin.
9. **Whole-sheet sanity** records warnings such as many uncertain rows or weak registration but never invents answers. Registration failure rejects the scan; row ambiguity goes to teacher review.
10. **Teacher review and save** keep the existing workflow. Saving remains disabled until every uncertain row has been explicitly reviewed.

## Diagnostics

Every `OmrResult` carries an `OmrDiagnostics` object. It is JSON/isolate-safe and contains:

- pipeline status and failure code;
- source and canonical dimensions;
- quality metrics and warnings;
- number of marker candidates;
- chosen fiducial coordinates and registration score;
- calibration blank baseline, MAD, and mark threshold;
- per-question A/B/C/D composite scores, selected decision, confidence, and decision reason.

`GradingScreen` exposes an expandable **Scan diagnostics** card on both successful scans and readable failures. The report is selectable and can be copied to the clipboard. This is intentionally prominent on the `omr_debug` branch so manual testing can report actionable evidence immediately.

## Compatibility

`OmrQuestion.marked`, `OmrQuestion.correct`, `OmrResult.correct`, `blank`, `needsReview`, `withMark`, gradebook snapshots, and current PDF coordinates remain compatible. Older serialized `OmrResult` JSON without diagnostics or decision metadata must still decode.

## Test strategy

- Keep the existing clean/off-center/perspective/double-mark/invalid-marker tests.
- Add stage-level tests for registration, rectification, local shadow resistance, calibration, faint/blank classification, and diagnostics serialization.
- Add a widget test proving diagnostics are visible/copyable and uncertainty still blocks saving.
- Keep manual image-generation tests separate from deterministic unit tests: the five image-generated sheets are the first human/device regression set, followed later by real A05 photographs.
- Final gate: `flutter analyze`, full `flutter test --concurrency=4`, and ARM64 debug APK build.

## Non-goals

No OMR paper redesign, ArUco/AprilTag markers, OpenCV dependency, ML model, auto-correction of handwriting, server diagnostics, or removal of teacher review.
