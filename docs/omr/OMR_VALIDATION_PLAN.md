# OMR validation and release gate

The scanner is safety-critical because its output becomes a student record. Automated tests protect geometry and ambiguity rules, but a release must not be described as camera-validated until the physical matrix below passes.

## Implemented safeguards

- The runner-up is the true second-darkest option, not merely the previous best.
- Two similarly dark options are marked ambiguous.
- Fiducial candidates must be dense, isolated dark squares with plausible rectangular geometry.
- Missing or implausible fiducials stop grading.
- Every detected answer is editable before save.
- Blank or low-confidence rows require an explicit teacher confirmation.
- Saved results include the immutable answer-key snapshot used for grading.
- Analytics records only counts and corrections, never the image, student name, marks, or score.

## Physical test matrix

Test at least three low/mid-range Android phones and one higher-end phone. For every device, test:

- daylight, fluorescent light, and low light;
- pencil, blue pen, and black pen;
- light, medium, and heavy fills;
- one double-mark per row;
- erased answers and strike-through corrections;
- 0, 90, 180, and 270 degree EXIF orientation;
- perspective tilt up to the maximum capture guide allows;
- shadows across one corner and across the bubble grid;
- clean, faint, low-ink, photocopied, and slightly crumpled sheets;
- full answer box, partially cropped fiducial, and unrelated dark objects;
- 5, 10, and the maximum supported question count.

## Required metrics

Record per device and condition:

- fiducial detection success rate;
- false fiducial acceptance rate;
- per-bubble precision and recall;
- double-mark rejection rate;
- teacher correction rate;
- processing time;
- crash and memory behaviour.

Release only after the team defines numerical thresholds and signs a test report. Every false acceptance must be treated more seriously than a false rejection because the teacher can retake a rejected image, while a silent incorrect mark can harm a student record.

## `omr_debug` staged pipeline

The `omr_debug` branch replaces direct photo-coordinate bubble sampling with an explicit diagnostic pipeline:

1. decode/orient and cap image size;
2. capture-quality measurement (resolution, exposure clipping, blur variance);
3. adaptive dark-mask connected-component marker detection;
4. four-marker geometry validation;
5. projective rectification into a fixed canonical OMR image;
6. local bubble-versus-paper contrast measurement at known template coordinates;
7. per-sheet blank-distribution calibration;
8. conservative marked / blank / ambiguous row classification;
9. whole-sheet warnings; and
10. teacher review before persistence.

The branch deliberately keeps the existing four-square paper format. It does not use circle detection, ML, OCR, OpenCV, or coded fiducials.

### Debug handoff

Every readable scan now carries copyable **Scan diagnostics**. A useful bug report from manual testing should include the original image plus the copied report. The report contains:

- pipeline status and typed failure code;
- source/canonical dimensions;
- exposure and blur metrics;
- marker candidate count, selected marker coordinates, geometry score, and registration note;
- per-stage processing timings;
- blank baseline, MAD, and calibrated mark threshold; and
- per-question A/B/C/D scores, decision, confidence, and reason.

This makes the first investigation question "which stage failed?" answerable from the report itself.

## Initial image-generated smoke set

Before printing physical sheets, run the five image-generated manual fixtures supplied in the OMR design conversation through **Choose image**. These are development smoke tests, not release evidence.

| Fixture | Expected condition | Expected marks |
|---|---|---|
| 01 clean | sharp, mostly top-down baseline | `1=B 2=D 3=A 4=C 5=B 6=D 7=C 8=A 9=B 10=D` |
| 02 perspective | mild rotation / perspective | same 10 answers |
| 03 lighting | uneven soft shadow / brightness gradient | same 10 answers |
| 04 degraded | mild blur/noise/reduced contrast | same 10 answers, or conservative review rather than a confident wrong read |
| 05 ambiguity | Q3 deliberately has A+B; Q7 is intentionally faint C | Q3 must require review; Q7 may be C with low confidence or require review; all other rows match the baseline key |

For each run, record: pass/fail, any wrong confident answer, number of rows requiring review, and the copied diagnostics. A confident wrong read is more severe than a rejected/ambiguous row.

These five images are only the Level-A smoke set. Physical A05 photographs remain mandatory before the OMR feature can be described as camera-validated.

## Template-fidelity lesson from the first generated smoke sheet

The first purely image-generated smoke sheet was **not** a valid Bayaz OMR fixture even though it looked visually plausible. Manual testing on 2026-08-26 showed confident fiducial registration (`0.975`) but incorrect/blank row reads. The copied diagnostics and image inspection showed why: the generator moved the bubble grid relative to the four markers. The generated first row was around normalized `y=0.27`, while the shipping ten-question Bayaz template expects Q1 around `y=0.15`; the columns also differed.

This is now treated as a test-fixture failure, not a reason to retune Bayaz to arbitrary OMR layouts. `omr_debug` verifies the expected bubble-outline geometry after rectification and returns `templateMismatch` when four plausible markers surround a non-Bayaz grid. The UI tells the tester to use an answer box from a PDF created by Bayaz and keeps the full diagnostic report available.

For future synthetic/manual fixtures, **the base answer grid must come from the real Bayaz PDF geometry**. Generative image tools may be used for photographic appearance or adversarial variation only if the marker/bubble geometry is preserved. Any generated image that fails the template-fidelity check is not valid grading ground truth.
