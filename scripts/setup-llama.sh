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
CM="$SRC/CMakeLists.txt"

# Patch the package's wrapper CMakeLists (idempotent). Two fixes needed to make
# the CPU backend register in an Android app (else model load = "available
# devices: 0"):
#   1. add_compile_definitions(GGML_USE_CPU) — the wrapper only sets GGML_USE_CPU
#      on its `mtmd` target, NOT on the `ggml` target where ggml-backend-reg.cpp
#      lives, so the CPU backend is never statically registered. Force it globally.
#   2. GGML_VULKAN OFF — CPU-only build for budget devices (no working Adreno GPU).
# (Also: keep BUILD_SHARED_LIBS=ON so libllama.so exports all FFI symbols like
# llama_sampler_chain_init; ANDROID_STL=c++_shared; and set ModelParams.mainGpu=-1
# in Dart so load validation passes with 0 GPU devices — see llama_cpp_service.dart.)
grep -q "add_compile_definitions(GGML_USE_CPU)" "$CM" || \
  sed -i 's|add_subdirectory(llama.cpp)|add_compile_definitions(GGML_USE_CPU)\nadd_subdirectory(llama.cpp)|' "$CM"
sed -i 's|set(GGML_VULKAN ON |set(GGML_VULKAN OFF |' "$CM"

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
