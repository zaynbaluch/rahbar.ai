# Android release checklist

1. Confirm `git status` is clean and all tests pass.
2. Run `bash scripts/check-environment.sh`.
3. Confirm the production application ID and canonical brand name.
4. Configure the organization-owned release keystore outside Git.
5. Run `flutter analyze` and `flutter test`.
6. Run `flutter build appbundle --release` and `flutter build apk --release`.
7. Verify the APK signature with `apksigner verify --verbose --print-certs`.
8. Record SHA-256 checksums for release artifacts.
9. Install the APK on supported Android versions and complete the smoke-test script.
10. Archive the release notes, checksums, signing-certificate fingerprint, and source commit.
