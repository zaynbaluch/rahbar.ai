#!/usr/bin/env python3
"""Local quality bake-off: run each model on each grounded prompt (greedy),
matching the app's sampler (temp 0, repeat-penalty 1.15, nCtx 4096). Captures
output + llama.cpp's own tok/s. Quality is hardware-independent, so x86 results
transfer; only the tok/s numbers differ from the phone.
"""
import json, os, pathlib, subprocess, re, sys, time

ROOT = pathlib.Path("/tmp/claude-1000/-mnt-Personal-Atelier-rahbar-ai/46278caa-3a73-41b1-bf8e-8814a56f0d51/scratchpad")
CLI = os.path.expanduser("~/llama-bakeoff/build/bin/llama-cli")
MODELS = ROOT / "models"
PROMPTS = ROOT / "prompts"
OUT = ROOT / "bakeoff_out"
OUT.mkdir(exist_ok=True)

MODEL_FILES = {
    "qwen3-1.7b": "Qwen3-1.7B-Q4_K_M.gguf",
    "lfm2-1.2b": "LFM2-1.2B-Q4_K_M.gguf",
    "lfm2-700m": "LFM2-700M-Q4_K_M.gguf",
}
# Qwen3 is a hybrid-thinking model; the app runs it non-thinking. Disable think.
THINK_OFF = {"qwen3-1.7b": ['--chat-template-kwargs', '{"enable_thinking":false}']}


def run(model_key, slug, rec):
    mf = str(MODELS / MODEL_FILES[model_key])
    cmd = [
        CLI, "-m", mf, "--jinja",
        "-sys", rec["system"], "-p", rec["user"],
        "-n", "1000", "-c", "4096",
        "--temp", "0", "--repeat-penalty", "1.15",
        "-no-cnv", "-st", "--no-warmup", "-t", "8",
    ] + THINK_OFF.get(model_key, [])
    t0 = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          errors="replace", timeout=1200)
    dt = time.time() - t0
    text = proc.stdout
    combined = proc.stdout + "\n" + proc.stderr
    tally = re.search(r"Generation:\s*([\d.]+)\s*t/s", combined)
    prefill = re.search(r"Prompt:\s*([\d.]+)\s*t/s", combined)
    meta = {
        "model": model_key, "slug": slug, "wall_s": round(dt, 1),
        "gen_tps": float(tally.group(1)) if tally else None,
        "prefill_tps": float(prefill.group(1)) if prefill else None,
    }
    (OUT / f"{slug}__{model_key}.txt").write_text(text, encoding="utf-8")
    return meta


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None  # optional model filter
    index = json.loads((PROMPTS / "index.json").read_text())
    results = []
    for model_key in MODEL_FILES:
        if only and model_key != only:
            continue
        for slug in index:
            rec = json.loads((PROMPTS / f"{slug}.json").read_text())
            m = run(model_key, slug, rec)
            results.append(m)
            print(f"{model_key:12} {slug:40} gen={m['gen_tps']} prefill={m['prefill_tps']} wall={m['wall_s']}s", flush=True)
    (OUT / "timing.json").write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
