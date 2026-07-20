# Run Bayaz AI on Android

## Required toolchain

Use the versions pinned by the repository configuration and setup documents:

- Flutter 3.44.4 stable
- Dart 3.12.2
- Android Gradle Plugin 8.11.1
- Gradle 8.13
- Kotlin 2.2.20
- Java 17
- Android NDK 27.0.12077973

## 1. Restore the native runtime

From the repository root:

```bash
bash scripts/setup-llama.sh
bash scripts/check-environment.sh
```

The large native dependency is not stored in this source ZIP.

## 2. Resolve Flutter packages

```bash
cd app
flutter pub get
```

This creates `pubspec.lock`. Review and commit that lockfile in the real repository.

## 3. Validate

```bash
cd ..
python scripts/validation/validate_repository.py
cd app
flutter analyze
flutter test
```

The Python validator performs structural checks only. It does not replace Flutter analysis, Flutter tests, an Android build, model inference testing, or physical-camera OMR testing.

## 4. Run on a phone

Enable Android developer options and USB debugging, connect the device, then run:

```bash
flutter devices
flutter run
```

## 5. Build a release APK

Keep signing material outside Git. Copy the template and point it to the organization-controlled keystore:

```bash
cp android/key.properties.example android/key.properties
flutter build apk --release
```

Never place keystores, passwords, certificates, or private signing keys in a delivery ZIP or Git commit.
