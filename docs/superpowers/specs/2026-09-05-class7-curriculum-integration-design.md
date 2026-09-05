# Class 7 Curriculum Integration Design

## Goal
Make Bayaz safely serve the correct bundled curriculum and RAG databases for exactly three supported teaching contexts: Class 6 General Science, Class 7 General Science, and Class 7 History. No screen may display one context while reading another context's data.

## Constraints
- Keep existing Class 6 General Science database paths working.
- Bundle Class 7 curriculum data; no network is required for curriculum assets.
- Keep optional BGE and LFM model download behavior unchanged.
- Unknown non-empty class/subject codes fail explicitly instead of silently using Class 6.
- Legacy/custom flows with no class/subject codes may keep Class 6 General Science as the compatibility default.
- Do not add Computer Science, Mathematics, English, or fake modules.
- Preserve saved-work TeachingContext metadata and OMR/test flows.
- Preserve current content_pack.db and curriculum.db schemas.

## Architecture

### Module registry
Add a small registry beside the curriculum catalog. Each supported module records module id, class code, subject code, content asset path, and RAG asset path. Catalog tests cross-check every selectable subject against this registry.

### ContentService
ContentService accepts an optional TeachingContext. init() resolves the module, copies the correct bundled content database to a module-specific application-support filename, and opens it read-only. A context switch opens the next database before closing the current database.

### Topic picker
The picker constructs its owned ContentService with the initial TeachingContext. When Change selects another context, the service switches modules and reloads topics before the visible context is updated. This prevents a new label being shown over an old content database.

### RagService
RagService accepts an optional TeachingContext, resolves its RAG asset from the same registry, and copies it to a module-specific support filename. Generation and Ask Bayaz construct RagService from the active teaching context.

### Ask Bayaz propagation
ClarificationScreen receives TeachingContext?. Curriculum lesson/test screens pass their existing context into it. GenerationScreen passes its context to both RAG and follow-up clarification. Saved work already persists TeachingContext, so reopened work keeps the correct module.

### Assets
Class 7 assets live at:
- assets/curricula/pk/class7/general_science/content_pack.db
- assets/curricula/pk/class7/general_science/curriculum.db
- assets/curricula/pk/class7/history/content_pack.db
- assets/curricula/pk/class7/history/curriculum.db

pubspec.yaml includes both subject directories. runtime_manifest.json lists content and RAG resources for each Class 7 subject. Existing Class 6 entries remain unchanged.

## UX behavior
Onboarding and Settings already render CurriculumCatalog.classes, so adding Class 7 to the catalog exposes the new choices automatically. The existing workflow resolver and selector handle multiple class/subject combinations. Context switching refreshes the topic picker in place.

## Failure behavior
- Unknown coded context: StateError; never Class 6 fallback.
- Missing/corrupt DB: existing screen error handling.
- Missing optional BGE model: existing ungrounded custom-generation fallback.
- Missing optional LFM model: existing setup/error flow.

## Verification
- Unit tests for module routing, catalog support, and unknown-context rejection.
- Widget test for topic reload on context switch.
- Widget tests that Ask Bayaz receives TeachingContext.
- Manifest test that each catalog module has bundled content and RAG descriptors.
- Python SQLite audit for integrity, row counts, 1536-byte embedding blobs, and no NULL embeddings.
- If Flutter tooling is unavailable, record that limitation rather than claiming Dart tests/build passed.
