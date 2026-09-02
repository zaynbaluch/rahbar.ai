# Deferred OMR Work

This item is intentionally deferred from the current UI/generation polish pass.

## OMR reliability

- Build a real-photo validation corpus across shadows, skew, perspective, blur, printer variation, pen types, and partial framing.
- First improve the existing four-fiducial pipeline with canonical perspective normalization plus adaptive/local thresholding and local bubble contrast scoring.
- Re-tune confidence/ambiguity thresholds from measured data rather than synthetic sheets.
- Only consider coded fiducials (for example ArUco-style markers) if the improved existing paper format still misses the reliability target.
- Preserve teacher review for uncertain marks even after detection improves.
