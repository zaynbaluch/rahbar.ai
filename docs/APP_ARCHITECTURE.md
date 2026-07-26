# App Architecture

## Runtime boundary

Bayaz AI is currently a local-first Flutter/Android application. The app starts without a network service, analytics scheduler, or cloud account.

```text
Flutter UI
  -> bundled curriculum databases
  -> local library and grading stores
  -> PDF and OMR utilities
  -> optional app-managed local AI model files
```

## Default content path

Verified lesson-plan sections and MCQs are read from the bundled content pack. This remains the default path because it is fast, available offline, and reviewable before release.

## Optional AI path

Custom generation and clarification chat use llama.cpp through the vendored `llama_cpp_dart` binding. Model files are not stored in this repository. The bundled runtime manifest may list a direct provider URL, exact size, and SHA-256 checksum. The app downloads the file into private storage and verifies it before use.

There is no remote resource catalogue, catalogue signing system, anti-rollback sequence, or app backend in this MVP.

## Local data

The app stores onboarding preferences, recent topics, saved content, and grading results locally. The app does not automatically upload these records or run background synchronization.

## Deferred boundaries

Backend analytics, student handover, school administration, licensing, payments, district reporting, and APK website distribution are research-only. See `../research/README.md`.
