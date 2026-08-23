# Run Rahbar AI on an Android phone

## 1. Use the project SDK baseline

Use Flutter 3.44.4 stable, which includes Dart 3.12.2. Confirm with:

```bash
flutter --version
```

Do not run `flutter upgrade` for this project before the first validation build.

## 2. Restore the local llama.cpp dependency

The uploaded source archive did not include `third_party/llama_cpp_dart`, although `app/pubspec.yaml` references it as a local path dependency.

From the repository root, run the existing setup script:

```bash
bash scripts/setup-llama.sh
```

Follow any Android NDK requirements printed by that script.

## 3. Resolve and validate the Flutter app

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

The lockfile has been retained, so use `flutter pub get`, not `flutter pub upgrade`.

## 4. Connect the phone

Enable Developer options and USB debugging on the Android phone, connect it, then run:

```bash
flutter devices
flutter run
```

To install a release-mode build using the project's current debug signing configuration:

```bash
flutter run --release
```

## Local-model note

The verified curriculum content-pack path works from the bundled SQLite databases. The custom-topic fallback still requires its existing local model files and setup; the UI clearly marks that path as slower and review-required.
