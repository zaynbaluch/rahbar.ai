#!/usr/bin/env bash
# Boot the budget-device emulator, install, and launch the Rahbar AI app.
# Usage:  bash scripts/run-app.sh
set -e

export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_AVD_HOME="$HOME/.config/.android/avd"
export ANDROID_SDK_HOME="$HOME/.config/.android"
export PATH="$HOME/development/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:/opt/android-sdk/cmdline-tools/latest/bin:$PATH"

APK="app/build/app/outputs/flutter-apk/app-debug.apk"

# 1. Boot the emulator if not already running.
if ! adb devices | grep -q emulator; then
  echo "▶ Booting emulator (a window will open)…"
  nohup emulator -avd rahbar_budget_device -no-snapshot -netdelay none -netspeed full >/tmp/rahbar-emulator.log 2>&1 &
  disown
fi

echo "▶ Waiting for device to finish booting…"
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
echo "✓ Emulator ready."

# 2. Build the APK if missing.
if [ ! -f "$APK" ]; then
  echo "▶ APK not found — building (first build is slow)…"
  flutter build apk --debug -t app/lib/main.dart
fi

# 3. Install + launch.
echo "▶ Installing app…"
adb install -r "$APK"
echo "▶ Launching app…"
adb shell am start -n com.rahbarai.rahbar_ai/.MainActivity

cat <<'EOF'

✓ App launched on the emulator.
  In the app:
    1. Pick a model (start with "SmolLM 135M" — smallest/fastest).
    2. Optionally edit the prompt.
    3. Tap "Generate on-device".
  First run downloads the model (~135 MB, one time), then generates OFFLINE.
  (Note: generation currently uses the model's own knowledge — RAG grounding
   from the textbook is the next milestone, not wired in yet.)
EOF
