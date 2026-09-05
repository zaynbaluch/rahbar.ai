# Pinned Android build toolchain

The application is pinned to Flutter 3.44.4 and Dart 3.12.2 through `app/.fvmrc` and `app/.metadata`. Run `flutter pub get` to generate the lockfile after transferring this source package.

The Android build uses:

- Android Gradle Plugin 8.11.1
- Gradle 9.1.0
- JDK 17 bytecode target
- Android SDK platform 36
- Android Build Tools 35.0.0
- Android NDK 28.2.13676358
- Android command-line tools build 14742923

Run `bash scripts/bootstrap-toolchain.sh` on Linux x86_64 to install the pinned Flutter and Android command-line tools under `~/.local/share/bayaz-toolchain`. The script does not install system packages and requires `curl`, `tar`, `unzip`, `git`, and Java.

Then run:

```bash
bash scripts/setup-llama.sh
bash scripts/check-environment.sh
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

`scripts/setup-llama.sh` derives the Android SDK from `ANDROID_SDK_ROOT`, then `ANDROID_HOME`, then the bootstrap location above. It refuses to build against a different `llama_cpp_dart` checkout, defaults to the pinned NDK `28.2.13676358`, and builds the arm64 runtime with an Android API 24 floor. These defaults match the Flutter 3.44 application baseline. Supported overrides are:

```text
ANDROID_NDK=/absolute/path/to/ndk/28.2.13676358
ANDROID_NDK_VERSION=28.2.13676358
ANDROID_PLATFORM=android-24
LLAMA_DART_TAG=v0.2.0
BUILD_JOBS=4
```

Do not raise `ANDROID_PLATFORM` above the app's minimum SDK: doing so can produce native libraries that install but fail to load on older supported devices. Do not change `LLAMA_DART_TAG` without updating the Dart integration and `docs/decisions/ADR-002-on-device-inference.md`.

The Android application is restricted to `arm64-v8a` because that is the ABI produced by the pinned native setup. Do not remove the Gradle ABI filter unless equivalent native libraries are built, packaged, and tested for every additional ABI.

The repository uses AGP 8.11.1 with Gradle 9.1.0 and Kotlin 2.3.20. AGP 8.11.1 documents Gradle 8.13 as its *minimum* supported version; this repository runs a newer Gradle and has produced a debug APK on that combination. JDK 17 and Build Tools 35.0.0 remain unchanged; the repository now pins NDK 28.2.13676358 for native plugin compatibility. Do not upgrade one component independently without checking the compatibility table, and do not downgrade Gradle or Kotlin without a specific documented incompatibility.

## Release signing

Release builds intentionally fail when no signing identity is configured. Either copy `app/android/key.properties.example` to `app/android/key.properties` and fill it locally, or set these environment variables:

```text
BAYAZ_KEYSTORE_PATH
BAYAZ_KEYSTORE_PASSWORD
BAYAZ_KEY_ALIAS
BAYAZ_KEY_PASSWORD
```

The keystore and credentials must never be committed. Back up the production key in two controlled locations because Android updates must remain signed by the same identity.
