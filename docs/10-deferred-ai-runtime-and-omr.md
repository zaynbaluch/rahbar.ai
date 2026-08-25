# Deferred AI Runtime and OMR Work

These items are intentionally deferred from the current UI/generation polish pass.

## Gemma 4 Multi-Token Prediction (MTP)

- Test Gemma 4 MTP/speculative decoding in an isolated runtime fork/experiment.
- Do **not** patch the shipping Bayaz inference stack for MTP until the runtime path is proven on the Samsung SM-A055F baseline.
- The current Bayaz binding is `llama_cpp_dart` 0.2.0 with llama.cpp `b8595b16e` (2025-11-09), before Gemma 4 support.
- The current `llama_cpp_dart` 0.9 development line supports Gemma 4, but removed its Gemma-4 NextN/MTP implementation because it depended on private/ABI-fragile llama.cpp APIs. Classic target+draft speculative decoding is separate and can be evaluated later.
- Measure: load memory, time-to-first-token, decode tokens/sec, thermal throttling, and end-to-end 10-MCQ latency on the A05 before considering adoption.

## OMR reliability

- Build a real-photo validation corpus across shadows, skew, perspective, blur, printer variation, pen types, and partial framing.
- First improve the existing four-fiducial pipeline with canonical perspective normalization plus adaptive/local thresholding and local bubble contrast scoring.
- Re-tune confidence/ambiguity thresholds from measured data rather than synthetic sheets.
- Only consider coded fiducials (for example ArUco-style markers) if the improved existing paper format still misses the reliability target.
- Preserve teacher review for uncertain marks even after detection improves.
