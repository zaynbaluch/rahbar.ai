# Bayaz AI Flutter App

The app is an offline-first teacher tool for the current Class 6 General Science MVP.

## Main workflows

1. Complete the three-step teacher setup.
2. Open a recent topic or browse Class 6 -> General Science -> topic.
3. Use verified stored lesson plans and MCQ papers by default.
4. Optionally generate custom material or ask for clarification after installing approved local models.
5. Export material, save it to the library, or grade answer sheets with teacher confirmation.

## Local resources

`assets/config/runtime_manifest.json` lists bundled coursework and optional AI models. A downloadable model entry must include a direct HTTPS URL, exact byte size, and SHA-256 checksum. The app performs a direct download, verifies the checksum, and stores the file in private app storage.

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
