# Local AI Generation Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve long-running local generation feedback and make Offline AI download state consistent across the app without changing generation semantics.

**Architecture:** Keep the existing streaming generation and resource managers. Derive deterministic progress from already-streamed structured output, replace manual frame timers with animated WebP assets, and route Home/Settings through one app-scoped download controller.

**Tech Stack:** Flutter/Dart, llama_cpp_dart 0.2.0 (unchanged in committed work), ffmpeg for asset encoding, existing ResourceManager/LocalAiResources.

**Spec:** `docs/superpowers/specs/2026-08-25-local-ai-generation-polish-design.md`

## Global Constraints

- Samsung SM-A055F / approximately 4 GB RAM is the minimum hardware baseline.
- Preserve rotating long-operation messages.
- Footer copy is `Please keep this screen open.`
- No new animation artwork or interpolated frames.
- No OMR changes, Urdu translation, or report-system changes.
- MCQ prompt change stays minimal: at most two student-facing/source-scaffolding instructions.

---

### Task 1: Animated WebP playback

**Files:**
- Create: `app/assets/ui/animations/grading_complete.webp`
- Create: `app/assets/ui/animations/lesson_saved.webp`
- Create: `app/assets/ui/animations/scanning_answers.webp`
- Create: `app/assets/ui/animations/test_ready.webp`
- Modify: `app/lib/design_system/components/frame_animation.dart`
- Test: `app/test/design_system/frame_animation_test.dart`

**Interfaces:**
- Consumes: current `BayazFrameAnimation(name:, size:, loop:)` call sites.
- Produces: same widget API; normal motion uses animated WebP, reduced motion uses frame `12.png`.

- [ ] Write a widget test asserting normal playback resolves `assets/ui/animations/<name>.webp` and reduced-motion resolves the final PNG.
- [ ] Run the focused test and verify RED because the widget still resolves individual numbered PNG frames.
- [ ] Encode each existing 12-frame directory with ffmpeg at 12 fps, looping forever, without interpolation.
- [ ] Replace timer/frame state with direct animated-WebP playback and reduced-motion fallback.
- [ ] Run focused animation tests and existing long-operation/grading tests.
- [ ] Commit `ui: use animated WebP operation artwork`.

### Task 2: Real streamed generation progress and concise copy

**Files:**
- Create: `app/lib/features/generation/generation_progress.dart`
- Modify: `app/lib/design_system/components/long_operation_panel.dart`
- Modify: `app/lib/features/generation/generation_screen.dart`
- Test: `app/test/features/generation/generation_progress_test.dart`
- Test: `app/test/features/generation/custom_test_flow_test.dart`
- Test: `app/test/features/generation/custom_lesson_flow_test.dart`

**Interfaces:**
- Produces: `GenerationProgress.mcq(String output, int expectedCount)` and `GenerationProgress.lesson(String output)` returning completed/total milestones.
- `LongOperationPanel` accepts optional `double? progress` and `String? progressLabel`.

- [ ] Write parser-unit tests for partial 10-question output (e.g. 3 complete => 3/10) and partial lesson output with completed section bodies.
- [ ] Run focused tests and verify RED because no progress helper exists.
- [ ] Implement conservative structural progress parsing.
- [ ] Add optional determinate progress UI while retaining rotating messages and animation.
- [ ] Change footer to exactly `Please keep this screen open.`
- [ ] Wire generation-phase buffer progress into dedicated custom test and lesson flows; keep preparing/retrieving/loading phases indeterminate.
- [ ] Run focused generation tests plus compact/large-text UI tests.
- [ ] Commit `ui: show real local generation progress`.

### Task 3: Minimal MCQ source-scaffolding prompt fix

**Files:**
- Modify: `app/assets/prompts/mcq.md`
- Test: `app/test/features/rag/rag_prompt_test.dart` or nearest existing prompt test.

**Interfaces:**
- Existing prompt placeholders and GBNF output contract remain unchanged.

- [ ] Add a prompt assertion test for the new standalone/student-facing rule.
- [ ] Run focused prompt test and verify RED.
- [ ] Add no more than two concise instructions: each question must stand alone for a student; never mention excerpts/sources/retrieval/chapter or section identifiers or ask what was/wasn't mentioned in them.
- [ ] Run prompt/RAG/parser tests.
- [ ] Commit `prompt: keep custom MCQs student facing`.

### Task 4: Shared Offline AI download state

**Files:**
- Modify: `app/lib/features/resources/background_ai_download_controller.dart`
- Modify: `app/lib/app/bayaz_shell.dart`
- Modify: `app/lib/features/curriculum/curriculum_home_screen.dart` only if state API changes require it.
- Modify: `app/lib/features/settings/settings_screen.dart`
- Modify: `app/lib/features/settings/resource_management_screen.dart`
- Test: `app/test/features/resources/background_ai_download_controller_test.dart`
- Test: `app/test/features/settings/resource_management_screen_test.dart`
- Test: `app/test/features/home_screen_test.dart`

**Interfaces:**
- `BayazShell` continues to own one `BackgroundAiDownloadController`.
- `SettingsScreen` accepts an optional controller and passes it to `ResourceManagementScreen`.
- Manual Settings download invokes the shared controller; both screens render the same broadcast state.
- Controller gains an explicit refresh/reset path after downloads are removed.

- [ ] Write a widget/controller test proving a download started in the shared controller renders `Downloading` in Settings and does not expose another download action.
- [ ] Run focused tests and verify RED because Settings owns unrelated local `_downloading` state.
- [ ] Extend controller state with enough readiness/install metadata for both surfaces and explicit refresh after external removal.
- [ ] Thread the controller from `BayazShell` through Home's Settings navigation into Settings/Offline AI.
- [ ] Replace Settings' independent download loop with shared-controller calls and stream rendering; retain removal via ResourceManager then refresh the controller.
- [ ] Run all resource/settings/home tests.
- [ ] Commit `fix: share Offline AI download state`.

### Task 5: Deferred-work note

**Files:**
- Create: `docs/10-deferred-omr.md`

- [ ] Document OMR deferred work: real-photo corpus, adaptive/local thresholding/canonicalization first, coded fiducials only if needed.
- [ ] Commit `docs: track deferred OMR work`.

### Task 6: Full committed-track verification

- [ ] Run `/home/m/fvm/versions/3.44.4/bin/flutter analyze` from `app`.
- [ ] Run `/home/m/fvm/versions/3.44.4/bin/flutter test` from `app`.
- [ ] Run `/home/m/fvm/versions/3.44.4/bin/flutter build apk --debug --target-platform android-arm64`.
- [ ] Record APK SHA-256 and verify Git status contains only known pre-existing unrelated untracked files.
