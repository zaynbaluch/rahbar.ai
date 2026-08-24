#!/usr/bin/env bash
# Build, install, and launch Bayaz AI on a connected Android device or emulator.
# Usage: bash scripts/run-app.sh [--release] [--no-build]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
BUILD_MODE="debug"
NO_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) BUILD_MODE="release" ;;
    --no-build) NO_BUILD=1 ;;
    -h|--help)
      sed -n '1,4p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

for command in flutter adb; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    echo "Run: bash scripts/bootstrap-toolchain.sh" >&2
    exit 127
  fi
done

if [[ ! -d "$REPO_ROOT/third_party/llama_cpp_dart" ]]; then
  echo "Missing third_party/llama_cpp_dart." >&2
  echo "Run: bash scripts/setup-llama.sh" >&2
  exit 1
fi

APK="$APP_DIR/build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"

if ! adb devices | awk 'NR>1 && $2 == "device" {found=1} END {exit !found}'; then
  echo "No ready Android device or emulator is connected." >&2
  echo "Start an emulator or connect a device with USB debugging enabled." >&2
  exit 1
fi

cd "$APP_DIR"
if [[ $NO_BUILD -eq 0 || ! -f "$APK" ]]; then
  flutter pub get
  flutter build apk "--$BUILD_MODE" -t lib/main.dart
fi

adb install -r "$APK"
adb shell am start -n com.rahbarai.rahbar_ai/.MainActivity

echo "Bayaz AI launched ($BUILD_MODE)."
