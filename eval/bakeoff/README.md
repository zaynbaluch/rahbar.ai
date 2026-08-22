# Generation model bake-off harness

Reproduces the LFM2-vs-Qwen3 speed/quality comparison behind ADR-003's 2026-07-10
decision. **Quality is hardware-independent**, so this runs locally (x86) against the
*real* grounded prompts; only the tok/s numbers differ from the phone (relative
ranking still holds).

## Steps

1. Build llama.cpp (recent enough for LFM2 — any 2025-11+ build):
   ```
   git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/llama-bakeoff
   cmake -B ~/llama-bakeoff/build -S ~/llama-bakeoff -DGGML_NATIVE=ON -DLLAMA_CURL=OFF
   cmake --build ~/llama-bakeoff/build -j --target llama-cli
   ```
2. Download the GGUFs (Q4_K_M) into `scratchpad/models/`: `LFM2-1.2B`, `LFM2-700M`
   from `LiquidAI/*-GGUF`, `Qwen3-1.7B` from `unsloth/Qwen3-1.7B-GGUF`.
3. Dump faithful grounded prompts (same bge retrieval + budget as the app):
   ```
   cd pipeline && uv run python -m src.dump_prompts <scratchpad>/prompts
   ```
4. `python3 bakeoff.py` → per-model outputs + `timing.json`.
5. `python3 grade.py` → structural grade (questions, ANSWER lines, difficulty tags).
6. `python3 gen_grammar.py` regenerates `mcq.gbnf`; test grammar with
   `llama-cli --grammar-file mcq.gbnf …` to confirm 10/10 valid schema.

The shipping grammar lives in `app/lib/features/generation/mcq_grammar.dart`.
