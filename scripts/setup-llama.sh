#!/usr/bin/env bash
# Vendor llama_cpp_dart (with its pinned llama.cpp submodule) and build the
# Android arm64 native runtime used by the app. The defaults intentionally
# match docs/setup/TOOLCHAIN.md and app/android/app/build.gradle.kts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LLAMA_DART_TAG="${LLAMA_DART_TAG:-v0.2.0}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"
TOOLCHAIN_ROOT="${BAYAZ_TOOLCHAIN_ROOT:-$HOME/.local/share/bayaz-toolchain}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$TOOLCHAIN_ROOT/android-sdk}}"
NDK="${ANDROID_NDK:-$ANDROID_SDK_ROOT/ndk/$ANDROID_NDK_VERSION}"
LLAMA_DIR="$ROOT_DIR/third_party/llama_cpp_dart"
SRC="$LLAMA_DIR/src"
CM="$SRC/CMakeLists.txt"
BUILD_DIR="$SRC/build-android"
JNI="$ROOT_DIR/app/android/app/src/main/jniLibs/arm64-v8a"

for command in git cmake sed grep; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing prerequisite: $command" >&2
    exit 127
  }
done

TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
if [[ ! -f "$TOOLCHAIN_FILE" ]]; then
  cat >&2 <<MSG
Android NDK $ANDROID_NDK_VERSION was not found at:
  $NDK

Set ANDROID_NDK to the exact NDK directory, or install the repository-pinned
Android toolchain described in docs/setup/TOOLCHAIN.md.
MSG
  exit 2
fi

mkdir -p "$ROOT_DIR/third_party"
if [[ ! -d "$LLAMA_DIR/.git" ]]; then
  rm -rf "$LLAMA_DIR"
  git clone --branch "$LLAMA_DART_TAG" --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/netdur/llama_cpp_dart "$LLAMA_DIR"
else
  current_tag="$(git -C "$LLAMA_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ "$current_tag" != "$LLAMA_DART_TAG" ]]; then
    cat >&2 <<MSG
Existing llama_cpp_dart checkout does not match the required tag.
  expected: $LLAMA_DART_TAG
  actual:   ${current_tag:-untagged checkout}

Remove third_party/llama_cpp_dart and rerun this script, or set
LLAMA_DART_TAG only after updating the Dart integration and ADR-002.
MSG
    exit 3
  fi
  git -C "$LLAMA_DIR" submodule update --init --recursive --depth 1
fi

if [[ ! -f "$CM" ]]; then
  echo "Missing llama_cpp_dart CMake project: $CM" >&2
  exit 4
fi

# The v0.2.0 wrapper does not propagate GGML_USE_CPU to the ggml target. Without
# it, Android reports zero available backends. Keep this patch idempotent and
# retain a CPU-only build for the current budget-device baseline.
grep -q "add_compile_definitions(GGML_USE_CPU)" "$CM" || \
  sed -i 's|add_subdirectory(llama.cpp)|add_compile_definitions(GGML_USE_CPU)\nadd_subdirectory(llama.cpp)|' "$CM"
sed -i 's|set(GGML_VULKAN ON |set(GGML_VULKAN OFF |' "$CM"

cmake -B "$BUILD_DIR" -S "$SRC" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_OPENMP=OFF \
  -DGGML_NATIVE=OFF \
  -DLLAMA_CURL=OFF
cmake --build "$BUILD_DIR" -j"${BUILD_JOBS:-4}" --target mtmd

mkdir -p "$JNI"
required_libraries=(
  "$BUILD_DIR/libmtmd.so"
  "$BUILD_DIR/bin/libllama.so"
  "$BUILD_DIR/bin/libggml.so"
  "$BUILD_DIR/bin/libggml-base.so"
  "$BUILD_DIR/bin/libggml-cpu.so"
  "$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
)
for library in "${required_libraries[@]}"; do
  if [[ ! -f "$library" ]]; then
    echo "Expected native library was not produced: $library" >&2
    exit 5
  fi
  cp "$library" "$JNI/"
done

echo "llama_cpp_dart $LLAMA_DART_TAG native runtime installed to $JNI"
echo "NDK: $ANDROID_NDK_VERSION; API floor: $ANDROID_PLATFORM; ABI: arm64-v8a"
