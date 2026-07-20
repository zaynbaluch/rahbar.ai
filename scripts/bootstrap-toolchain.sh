#!/usr/bin/env bash
# Install the repository-pinned Flutter and Android command-line toolchain.
# Linux x86_64 only. Downloads require access to Google-hosted release archives.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.4}"
ANDROID_CLI_BUILD="${ANDROID_CLI_BUILD:-14742923}"
ANDROID_API="${ANDROID_API:-36}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-35.0.0}"
ANDROID_NDK="${ANDROID_NDK_VERSION:-27.0.12077973}"
INSTALL_ROOT="${BAYAZ_TOOLCHAIN_ROOT:-$HOME/.local/share/bayaz-toolchain}"
FLUTTER_ROOT="$INSTALL_ROOT/flutter-$FLUTTER_VERSION"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$INSTALL_ROOT/android-sdk}"
CACHE_DIR="$INSTALL_ROOT/downloads"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) echo "This bootstrap script currently supports Linux x86_64 only." >&2; exit 2 ;;
esac

for command in curl tar unzip git java; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing prerequisite: $command" >&2
    exit 127
  }
done

mkdir -p "$CACHE_DIR" "$ANDROID_SDK_ROOT/cmdline-tools"

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  FLUTTER_ARCHIVE="$CACHE_DIR/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl --fail --location --retry 3 \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    --output "$FLUTTER_ARCHIVE"
  rm -rf "$INSTALL_ROOT/flutter" "$FLUTTER_ROOT"
  tar -xf "$FLUTTER_ARCHIVE" -C "$INSTALL_ROOT"
  mv "$INSTALL_ROOT/flutter" "$FLUTTER_ROOT"
fi

if [[ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  CLI_ARCHIVE="$CACHE_DIR/commandlinetools-linux-${ANDROID_CLI_BUILD}_latest.zip"
  curl --fail --location --retry 3 \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CLI_BUILD}_latest.zip" \
    --output "$CLI_ARCHIVE"
  rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest" "$CACHE_DIR/cmdline-tools"
  unzip -q "$CLI_ARCHIVE" -d "$CACHE_DIR"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv "$CACHE_DIR/cmdline-tools"/* "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
  rmdir "$CACHE_DIR/cmdline-tools"
fi

export PATH="$FLUTTER_ROOT/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"

yes | sdkmanager --licenses >/dev/null || true
sdkmanager \
  "platform-tools" \
  "platforms;android-$ANDROID_API" \
  "build-tools;$ANDROID_BUILD_TOOLS" \
  "ndk;$ANDROID_NDK" \
  "cmake;3.22.1"

"$FLUTTER_ROOT/bin/flutter" config --android-sdk "$ANDROID_SDK_ROOT"
"$FLUTTER_ROOT/bin/flutter" doctor -v

cat <<MSG

Toolchain installed.
Add these lines to your shell profile:
  export FLUTTER_ROOT="$FLUTTER_ROOT"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export PATH="\$FLUTTER_ROOT/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"
MSG
