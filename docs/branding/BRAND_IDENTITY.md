# Bayaz AI brand identity decision

## Canonical user-facing name

The canonical product name is **Bayaz AI**. All visible labels, onboarding copy, Android application labels, documentation written for teachers, future external materials, and curriculum-module metadata should use Bayaz AI.

The Android namespace and application ID currently remain `com.rahbarai.rahbar_ai`. They are technical identifiers inherited from the earlier prototype. Changing an Android application ID creates a different application identity and breaks in-place upgrades, stored-data continuity, signing continuity, managed-device rules, and any future package registration. A package migration must therefore be a deliberate release-management decision, not a visual cleanup task.

## Logo contrast rule

The primary logo contains a large white page shape and must not be placed directly on a white or very pale background. Use one of these treatments:

1. Primary blue (`#003CFF`) container with internal padding.
2. Primary blue hero panel.
3. An approved dark brand background.

Do not add an arbitrary drop shadow or outline to compensate for poor contrast. The implementation wraps the app-bar mark in a blue rounded square and keeps hero placements on blue.

## Splash screen

The native Android launch background is `#003CFF`, matching `AppColors.primary`. The white-and-gold mark remains legible while Flutter initializes. Both normal and Android 12+ splash resources must retain the same background value when regenerated.

## Layout rules

- App-bar mark: 42 × 42 logical pixels, 6 pixels internal padding.
- Home hero mark: approximately 68 × 68 logical pixels on compact phones.
- Decorative watermark: no larger than 132 × 132 logical pixels and clipped inside the card.
- Preserve aspect ratio with `BoxFit.contain`.
- Do not let the logo compete with the primary task title or overflow the card on 320-pixel-wide devices.

## Asset maintenance

PNG and WebP variants currently coexist because older screens reference both formats. New UI should prefer WebP for illustration assets and the canonical PNG for the transparent brand mark until the team approves a single optimized vector/raster pipeline. Remove obsolete duplicates only after an asset-reference check and a successful release build.
