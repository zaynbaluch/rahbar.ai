# Local AI Generation Polish Design

## Scope

This design implements the user-approved product changes around long-running local generation while preserving existing curriculum, RAG, storage, and grading behavior.

Committed scope:
- Replace the four 12-frame PNG timer animations with animated WebP files built from the existing frames only; do not invent or interpolate new artwork.
- Preserve the rotating human-friendly progress messages in `LongOperationPanel`.
- Replace the over-explaining footer with exactly `Please keep this screen open.`
- Add real custom-test progress by counting complete streamed MCQ blocks against 5/10/15.
- Add real custom-lesson progress by counting completed structured lesson sections against the existing prompt contract.
- Keep progress conservative: count only structurally complete milestones already present in streamed output; do not estimate time remaining.
- Add only minimal prompt guidance for student-facing MCQs: questions must stand alone and must not mention excerpts, sources, retrieval, or chapter/section identifiers.
- Unify Offline AI download state so Home and Settings observe and start the same download operation and cannot disagree about whether a download is active.
- Add a small deferred-work document for Gemma 4 MTP and OMR reliability work.

Explicitly deferred:
- No OMR algorithm changes.
- No Gemma 4 MTP implementation.
- No additional rendered animation frames.
- No Urdu translation pass.
- No report-system work.

## Download state architecture

`BackgroundAiDownloadController` remains the app-scoped owner created by `BayazShell`. It is extended into the single observable download state source used by both Home and Settings. `SettingsScreen` and `ResourceManagementScreen` receive that controller instead of creating an unrelated live download operation. File integrity remains owned by the existing `ResourceManager` / `LocalAiResources` implementation.

Manual download from Settings calls the same app-scoped controller used by automatic startup download. Settings renders progress from the controller stream and refreshes installed-file metadata after completion. Removing downloads remains a Settings maintenance action; after removal it forces the shared controller back to an inspectable not-ready state.

## Generation progress architecture

Generation already streams chunks into `_buffer`. Progress is derived from the sanitized current buffer every UI refresh:
- MCQ: count complete question blocks that have a Q header, four options, and an ANSWER line. Clamp to selected count.
- Lesson: count unique prompt section headers that have begun receiving non-empty content. The denominator is the fixed prompt section contract.

`LongOperationPanel` gains optional determinate progress data and a progress label while retaining its rotating message/animation behavior. Retrieval/model-loading phases remain indeterminate; determinate progress starts only during generation.

## Animation architecture

Each current frame directory is encoded to one looping animated WebP at 12 fps. `BayazFrameAnimation` displays the animated WebP directly for normal motion and the existing final PNG frame when `MediaQuery.disableAnimations` is true. The old individual frames can remain in the repository for source/editability, but runtime playback no longer swaps them with a Dart timer.

## Model experiment boundary

Gemma 4 is not part of the committed product-change track. The current app uses `llama_cpp_dart` 0.2.0 with llama.cpp commit `b8595b16e` (2025-11-09), which predates Gemma 4 support. Google documents the 1.1 GB / 0.84 GB E2B mobile figures as inference-memory estimates for LiteRT-LM, not GGUF file sizes. Therefore mobile Gemma requires a different runtime architecture, while GGUF Gemma requires a newer llama.cpp binding/runtime.

After committed changes pass full verification, perform a separate uncommitted experiment. Prefer the least-invasive Gemma 4 path that can actually run on the Samsung SM-A055F baseline. Do not implement MTP. If integration requires broad product refactoring, stop at a reproducible feasibility result rather than committing a half-migration.
