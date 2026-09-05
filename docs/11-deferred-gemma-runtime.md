# Deferred Gemma Runtime Work

Do not change the shipping Bayaz/LFM runtime yet. Revisit this only when we are ready to evaluate Gemma again on the Samsung SM-A055F (~4 GB RAM) baseline.

## TODO

- Update the Bayaz llama.cpp stack to a current Gemma-4-capable version. This will likely require migrating the pinned `llama_cpp_dart` 0.2.x integration to a modern compatible binding/runtime rather than swapping only the native library.
- Keep the runtime upgrade isolated in a branch/worktree until the existing LFM path and full app test suite remain stable.
- Benchmark Gemma 4 E2B QAT `UD-Q2_K_XL` against the previously tested QAT `UD-Q4_K_XL` before integrating either into Bayaz.
- Re-run the Urdu/science quality bake-off: factual correctness, Urdu quality, MCQ distractors, source faithfulness, formatting compliance, and hallucinations.
- Measure on the A05: model load time, grounded-prompt TTFT/prefill, decode tok/s, peak PSS/RSS/swap, thermal throttling, and end-to-end 5/10-question generation time.
- Check current llama.cpp Gemma 4 MTP / speculative-decoding support when the runtime is upgraded. Use only stable/public APIs; do not patch Bayaz around private llama.cpp ABI hooks.
- If the Flutter binding does not expose the needed MTP controls, evaluate a small binding addition/fork separately before touching production Bayaz.
- Keep LFM as the production default until Gemma clearly wins the quality/performance trade-off on the minimum device.
