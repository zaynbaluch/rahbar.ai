#!/usr/bin/env bash
# Build-time generation server — llama.cpp on the laptop GPU, serving the ~8B model that
# writes the content pack (ADR-008). Nothing to do with the phone's llama.cpp build
# (that's scripts/setup-llama.sh: arm64, CPU).
#
#   bash scripts/setup-genserver.sh --setup    # fetch llama.cpp + Qwen3-8B  (once)
#   bash scripts/setup-genserver.sh --serve    # run it (leave in its own terminal)
#
# **Vulkan, not CUDA.** llama.cpp publishes no prebuilt Linux CUDA binary, and building
# from source needs the CUDA toolkit, which needs root. Vulkan runs on the NVIDIA driver
# that is already installed, needs no toolkit and no sudo, and costs maybe 10-20% of CUDA's
# throughput — irrelevant for a one-off overnight run.
#
# Sizing for the RTX 4050 Laptop (6141 MiB, ~5.7 GB usable — the display is on the iGPU):
#   Qwen3-8B Q4_K_M weights   4.7 GB
#   KV cache @ 8192, q8_0     0.6 GB
#   compute buffers (with FA) ~0.4 GB
#                             -------
#                             ~5.7 GB  — it fits, but only just. On an OOM, fall back to
#   partial offload:          NGL=32 bash scripts/setup-genserver.sh --serve
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${GEN_LLAMA_BUILD:-b9986}"
SRC="${GEN_LLAMA_DIR:-$HOME/llama-vk}"
BIN="$SRC/llama-$BUILD"
MODEL_DIR="${GEN_MODEL_DIR:-$REPO/data/models}"
MODEL="${GEN_MODEL:-$MODEL_DIR/Qwen3-8B-Q4_K_M.gguf}"
# Qwen3-8B: Apache-2.0, strong instruction-following, same family as the ADR-003 bake-off's
# quality winner. Ungated, so no HF token needed.
MODEL_REPO="${GEN_MODEL_REPO:-Qwen/Qwen3-8B-GGUF}"
MODEL_FILE="${GEN_MODEL_FILE:-Qwen3-8B-Q4_K_M.gguf}"

# Vulkan enumerates the AMD iGPU first; the dGPU is Vulkan1. Check with:
#   LD_LIBRARY_PATH=$BIN $BIN/llama-server --list-devices
DEVICE="${DEVICE:-Vulkan1}"
NGL="${NGL:-99}"
CTX="${CTX:-8192}"
PORT="${PORT:-8080}"

setup() {
  if [ ! -x "$BIN/llama-server" ]; then
    echo "==> fetching llama.cpp $BUILD (vulkan, x64)"
    mkdir -p "$SRC"
    curl -fsSL -o /tmp/llama-vk.tar.gz \
      "https://github.com/ggml-org/llama.cpp/releases/download/$BUILD/llama-$BUILD-bin-ubuntu-vulkan-x64.tar.gz"
    tar xzf /tmp/llama-vk.tar.gz -C "$SRC"
  fi
  if [ ! -f "$MODEL" ]; then
    echo "==> fetching $MODEL_REPO / $MODEL_FILE (~4.7 GB)"
    mkdir -p "$MODEL_DIR"
    uv run --project "$REPO/pipeline" -- \
      hf download "$MODEL_REPO" "$MODEL_FILE" --local-dir "$MODEL_DIR"
  fi
  LD_LIBRARY_PATH="$BIN" "$BIN/llama-server" --list-devices
  echo "==> ready. Start it with: bash scripts/setup-genserver.sh --serve"
}

serve() {
  [ -f "$MODEL" ] || { echo "ERROR: no model at $MODEL — run --setup first"; exit 1; }
  # Single slot on purpose: llama.cpp splits -c across parallel slots, and 6 GB has no room
  # for 4 x 8192. The pipeline is checkpointed, so a long sequential run is fine.
  #
  # -fa on          flash-attention: smaller compute buffer, and makes a quantized KV safe
  # -ctk/-ctv q8_0  halves the KV cache; q8 is lossless enough for this workload
  # --cache-reuse   keeps the shared prefix (system prompt + curriculum excerpts) in the KV
  #                 cache across calls. Verification issues ~60 calls per topic that differ
  #                 only in the trailing question, so this turns a ~2.5k-token prefill into
  #                 ~150 tokens. It is the single biggest speed win in the whole run.
  exec env LD_LIBRARY_PATH="$BIN" "$BIN/llama-server" \
    -m "$MODEL" \
    --device "$DEVICE" -ngl "$NGL" -c "$CTX" \
    -fa on -ctk q8_0 -ctv q8_0 --cache-reuse 256 \
    --host 127.0.0.1 --port "$PORT" --alias qwen3-8b
}

case "${1:---serve}" in
  --setup|--build) setup ;;
  --serve) serve ;;
  *) echo "usage: $0 [--setup|--serve]"; exit 1 ;;
esac
