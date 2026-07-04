# ADR-001 — App framework: Flutter (Android-only)

**Status:** Accepted · **Date:** 2026-07-04

## Context

Rahbar AI must run a quantized SLM, an embedding model, vector search, and a polished UI
**on budget Android phones with 2–4 GB RAM**, fully offline. The developer is confident in
React Native, Flutter, and native Android/Kotlin, and initially leaned toward React Native
(familiarity + beautiful Tailwind-style UI) but flagged latency/speed as the top concern.

The decisive realization: **the LLM runs as native C++/LiteRT under *any* framework**, so
raw inference speed is roughly framework-independent. The real differentiators for *this*
workload are (1) **memory overhead** on constrained devices, (2) **maturity of the
on-device LLM binding**, and (3) UI/dev velocity.

## Options considered

| Option | Baseline memory | On-device LLM binding | UI velocity | Fit |
|---|---|---|---|---|
| **Flutter (Dart)** | ~120–130 MB (near-native) | **First-class** (flutter_gemma / LiteRT, actively maintained) | High | **Best balance** |
| Native Android (Kotlin) | ~4–10 MB (smallest) | Most direct (LiteRT / MediaPipe / llama.cpp JNI) | Lower (most code) | Strong; UI slower to build |
| React Native | ~180–190 MB, up to ~223–243 MB under load | Less mature (llama.rn) | High | Weakest for 2–4 GB AI workloads |

At 2–4 GB RAM with a ~1.5 GB model resident, every ~100 MB of framework overhead matters.
React Native's higher baseline + GC pauses + the least-mature LLM binding make it the worst
fit here despite the developer's familiarity. Native Android is leanest but costs UI
velocity and is overkill given Flutter's near-native footprint.

## Decision

**Use Flutter, targeting Android only.** It sits ~within ~10% of native memory, has the
most mature Flutter-native on-device LLM path (flutter_gemma over LiteRT), ships a single
codebase, and delivers the "beautiful UI" goal quickly. **Native Kotlin is the documented
fallback** if profiling later shows we must reclaim the last few hundred MB or microseconds.

Android-only is confirmed indefinitely: the target teachers do not own iOS devices or
laptops, so cross-platform buys nothing.

## Consequences

- We depend on flutter_gemma / LiteRT maturity (see [ADR-002](ADR-002-on-device-inference.md)).
- We must **profile peak RAM on a real 2–4 GB device early** (Week 1 spike) to confirm the
  Flutter + model combination fits; this is the main risk this ADR carries.
- UI can use Material 3 with a custom theme; no need for a JS/Tailwind stack.
- If memory proves too tight, the escape hatch is native Kotlin for the generation screen,
  or a smaller model — not a framework rewrite of the whole app.

## Sources

- Flutter vs React Native memory (2026): <https://www.bolderapps.com/blog-posts/flutter-vs-react-native-in-2026-why-the-new-architecture-and-impeller-2-0-changed-everything>
- RN vs Flutter benchmark: <https://www.dharma-yudistira.com/blogs/rn-vs-flutter-benchmark>
- Memory management comparison: <https://www.arhaminfo.com/2025/11/memory-management-flutter-react-native-explained.html>
- Native vs cross-platform performance: <https://www.techaheadcorp.com/blog/what-is-the-performance-of-flutter-vs-native-vs-react-native/>
