#!/usr/bin/env bash
# Vendor llama_cpp_dart (with its pinned llama.cpp submodule) for the app's
# on-device generation runtime. The Android NDK builds llama.cpp from this
# source, so the FFI bindings and native lib always match. Referenced as a
# path dependency in app/pubspec.yaml. See docs/decisions/ADR-002.
set -e
cd "$(dirname "$0")/.."
mkdir -p third_party
if [ ! -d third_party/llama_cpp_dart ]; then
  git clone --recurse-submodules --shallow-submodules \
    https://github.com/netdur/llama_cpp_dart third_party/llama_cpp_dart
else
  echo "third_party/llama_cpp_dart already present"
fi

# --- Build the native libs (libmtmd.so + llama/ggml) for Android arm64 and
# --- install into the app's jniLibs. Requires the Android NDK.
NDK=${ANDROID_NDK:-/opt/android-sdk/ndk/28.2.13676358}
SRC=third_party/llama_cpp_dart/src
# ANDROID_STL=c++_shared is REQUIRED: with the default c++_static, each .so gets
# its own C++ runtime and the ggml CPU-backend's static-initializer registration
# never runs across the separate shared libs → "available devices: 0" at model
# load. Shared STL fixes it; libc++_shared.so must be bundled too. (Also set
# GGML_VULKAN=OFF in src/CMakeLists.txt for the CPU-only build.)
cmake -B "$SRC/build-android" -S "$SRC" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DLLAMA_CURL=OFF
cmake --build "$SRC/build-android" -j4 --target mtmd
JNI=app/android/app/src/main/jniLibs/arm64-v8a
mkdir -p "$JNI"
cp "$SRC/build-android/libmtmd.so" "$SRC/build-android/bin/"lib{llama,ggml,ggml-base,ggml-cpu}.so "$JNI/"
cp "$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$JNI/"
echo "native libs installed to $JNI"
