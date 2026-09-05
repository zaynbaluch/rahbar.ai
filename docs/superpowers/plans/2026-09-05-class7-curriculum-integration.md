# Class 7 Curriculum Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route every curriculum and RAG workflow to the correct bundled database for Class 6 General Science, Class 7 General Science, and Class 7 History.

**Architecture:** A central CurriculumModuleRegistry maps teaching contexts to bundled content/RAG assets. ContentService and RagService become context-aware, while TopicPicker and Ask Bayaz propagate the active context so labels and backing databases cannot diverge.

**Tech Stack:** Flutter/Dart, sqlite3, rootBundle assets, existing BGE-small search, Flutter widget/unit tests, Python sqlite3 audit.

**Spec:** `docs/superpowers/specs/2026-09-05-class7-curriculum-integration-design.md`

## Global Constraints
- Supported contexts are exactly Class 6 General Science, Class 7 General Science, and Class 7 History.
- Existing Class 6 asset paths remain valid.
- Unknown non-empty class/subject codes throw instead of using Class 6.
- Null/legacy class and subject codes retain Class 6 General Science compatibility.
- Curriculum DBs remain bundled read-only assets.
- Existing BGE/LFM optional model setup is unchanged.
- No unrelated UI redesign or cleanup.

---

### Task 1: Module registry and catalog
**Files:** create `app/lib/features/curriculum/curriculum_module_registry.dart`; modify `curriculum_catalog.dart`; modify `curriculum_catalog_test.dart`; create `curriculum_module_registry_test.dart`.

**Interfaces:** `CurriculumModuleAssets(moduleId,classCode,subjectCode,contentAsset,ragAsset)`, `CurriculumModuleRegistry.resolve(TeachingContext?)`, `CurriculumModuleRegistry.byModuleId(String)`.

- [ ] Write failing tests for Class 7 Science+History, catalog-to-registry coverage, Class 7 History asset paths, null-context Class 6 compatibility, and unknown coded context rejection.
- [ ] Run focused tests and confirm RED.
- [ ] Implement registry and add module ids `curriculum.pk.class7.general_science` and `curriculum.pk.class7.history`.
- [ ] Re-run focused tests and confirm GREEN.
- [ ] Commit `feat: register class 7 curriculum modules`.

### Task 2: Bundle Class 7 assets
**Files:** add four DBs under `app/assets/curricula/pk/class7/...`; modify `app/pubspec.yaml`, `app/assets/config/runtime_manifest.json`, and `resource_manifest_test.dart`.

**Interfaces:** manifest uses content id `<moduleId>` and RAG id `<moduleId>.rag`; paths match the registry.

- [ ] Add failing production-manifest assertions for every catalog module's bundled content and RAG descriptor.
- [ ] Run manifest test and confirm RED.
- [ ] Copy finalized Class 7 DBs and add both asset directories to pubspec.
- [ ] Add four Class 7 resource descriptors with exact size and SHA-256.
- [ ] Run Python SQLite audit: integrity ok, 18 MCQs/topic, zero NULL embeddings, every embedding blob 1536 bytes.
- [ ] Re-run manifest test and confirm GREEN.
- [ ] Commit `feat: bundle class 7 curriculum assets`.

### Task 3: Context-aware ContentService and picker
**Files:** modify `content_service.dart`, `topic_picker_screen.dart`, `topic_picker_mode_test.dart`.

**Interfaces:** `ContentService({TeachingContext? teachingContext})`, `switchContext(TeachingContext?) -> Future<void>`, `activeModuleId`.

- [ ] Extend the picker test double with switchContext tracking and add a failing widget test that switches Class 6 Science to Class 7 History and refreshes topics.
- [ ] Run picker test and confirm RED.
- [ ] Implement module-specific copy/open logic that opens the candidate DB before closing the current DB.
- [ ] Update TopicPicker to initialize and switch ContentService by TeachingContext, then refresh topics and persist the new context.
- [ ] Re-run picker/curriculum tests and confirm GREEN.
- [ ] Commit `feat: switch content packs by teaching context`.

### Task 4: Context-aware RagService
**Files:** modify `rag_service.dart`, `generation_screen.dart`; create `rag_module_selection_test.dart`.

**Interfaces:** `RagService({TeachingContext? teachingContext, Duration embeddingTimeout = ...})` exposes `moduleId` and `curriculumAsset` for pure routing tests.

- [ ] Write failing routing test for Class 7 History/Science distinct RAG paths and unknown-context rejection.
- [ ] Run test and confirm RED.
- [ ] Resolve the RAG asset through the registry and use a module-specific support filename; leave BGE model loading unchanged.
- [ ] Initialize GenerationScreen's late-final RagService with widget.teachingContext.
- [ ] Re-run RAG/custom-generation tests and confirm GREEN.
- [ ] Commit `feat: route rag by curriculum context`.

### Task 5: Ask Bayaz context propagation
**Files:** modify `clarification_screen.dart`, `lesson_plan_view.dart`, `mcq_test_view.dart`, `generation_screen.dart`; modify corresponding chat/generation widget tests.

**Interfaces:** ClarificationScreen gains `TeachingContext? teachingContext` and initializes RagService with it.

- [ ] Add failing widget assertions that lesson/test Ask Bayaz screens carry the source TeachingContext.
- [ ] Run tests and confirm RED.
- [ ] Add ClarificationScreen context field and context-aware RagService initialization.
- [ ] Pass context from LessonPlanScreen, McqTestScreen, and GenerationScreen. Also pass TeachingContext into custom generated output widgets where omitted.
- [ ] Re-run chat/generation tests and confirm GREEN.
- [ ] Commit `fix: keep ask bayaz in the active curriculum`.

### Task 6: Subject-neutral shared prompt
**Files:** modify `app/assets/prompts/lesson_plan.md`; modify/add RAG prompt asset tests.

**Interfaces:** placeholders remain `{{class}}`, `{{subject}}`, `{{topic}}`, `{{slos}}`, and `{{context}}`.

- [ ] Add failing asset assertion that the lesson prompt has no Science-only authoring rule while retaining source-only grounding and class/subject placeholders.
- [ ] Run prompt tests and confirm RED.
- [ ] Replace Science-only wording with subject-neutral wording and keep low-resource/50-minute constraints.
- [ ] Re-run prompt tests and confirm GREEN.
- [ ] Commit `fix: generalize grounded lesson prompt across subjects`.

### Task 7: Final verification and cleanup
- [ ] Run focused Flutter tests for curriculum, picker, resources, RAG routing/prompts, chat, and lesson/test screens.
- [ ] Run full `flutter test` if Flutter is available; otherwise explicitly record unavailability.
- [ ] Run `flutter analyze` if available.
- [ ] Run final Python DB/manifest consistency audit and `git diff --check`.
- [ ] Inspect worktree and main checkout status. Restore only the incidental main `pipeline/uv.lock` change; preserve all pre-existing untracked files.
- [ ] Invoke verification-before-completion and report exact evidence.
