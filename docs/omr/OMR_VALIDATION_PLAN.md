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
