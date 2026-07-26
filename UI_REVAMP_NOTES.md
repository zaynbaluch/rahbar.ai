# Rahbar AI UI Revamp

## Scope

This revision redesigns the existing teacher workflow without adding a new product workflow.

Implemented areas:

- Material 3 blue/gold visual system with neutral reading surfaces.
- Reusable spacing, radius, color, card, status, empty-state, brand-header, and frame-animation components.
- Teacher home and chapter-grouped curriculum browser.
- Existing topic workspace for lesson-plan and verified-MCQ creation.
- Existing lesson-plan view with clearer timing, materials, outcomes, and section swapping.
- Existing MCQ-paper review with save, teacher key, PDF/print, and grading actions.
- Existing OMR camera/gallery grading with capture guidance and processing feedback.
- Library filters for existing saved lesson plans and tests.
- Results views built only from grading records already stored on the device.
- Branded Android launcher icon and launch screen.
- Bundled static artwork and dependency-free frame animations.

Direct corrections included in the agreed UI pass:

- Structured saved lesson plans reopen as structured lesson plans.
- Each MCQ paper now keeps a persistent ID so printed papers and saved results remain associated.
- Older saved tests without an embedded paper ID keep using their saved-file ID.
- The former developer model-spike entry is no longer exposed in teacher navigation.
- Topics with fewer than ten verified questions state the real available count.
- Obsolete home-screen widget expectations were updated.

## Explicit non-features

This revision does not add or advertise:

- QR paper lookup.
- Student rosters or class management.
- AI chat or an AI-tutor conversation screen.
- XP, streaks, locked lessons, or student gamification.
- Cloud synchronization.
- A new OMR algorithm.
- A new persistence framework.
- New curriculum or generated content.
- A replacement inference engine.

## Compatibility baseline

The project files remain the source of truth:

- Flutter 3.44.4 stable.
- Dart 3.12.2.
- Flutter revision `ad70ec4617166f1c38e5d2bfd388af71fda14f06`.
- Android Gradle Plugin 8.11.1.
- Kotlin 2.3.20.
- Gradle 9.1.0.
- Java 17.
- Existing `pubspec.lock` retained.

No SDK, Gradle, Kotlin, or package migration was performed.
