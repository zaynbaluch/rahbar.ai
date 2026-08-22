"""Build-time LLM client — a local llama-server (CUDA) speaking the OpenAI API.

Generation moved off the phone (ADR-003 / ADR-008): a ~8B model on the laptop GPU
produces the content bank once, so the app can serve it instantly. Quality, not
speed, is the constraint here — an overnight run is fine.

Start the server first (see `scripts/setup-genserver.sh`):

    llama-server -m models/qwen3-8b-q4_k_m.gguf -ngl 99 -c 8192 --parallel 4 --port 8080

Output is constrained with a **JSON schema** (llama.cpp compiles it to a GBNF
grammar, the same mechanism as the app's `mcq_grammar.dart`), so a parse failure is
a server/model problem, never a formatting one.

Every call retries with backoff. A call that never succeeds raises — the caller must
then leave its checkpoint unwritten so the unit is retried on the next run, rather
than persisting a partial result.
"""

from __future__ import annotations

import json
import os
import time

import httpx

BASE_URL = os.environ.get("RAHBAR_LLM_URL", "http://127.0.0.1:8080")
MODEL = os.environ.get("RAHBAR_LLM_MODEL", "qwen3-8b")
TIMEOUT = float(os.environ.get("RAHBAR_LLM_TIMEOUT", "900"))
MAX_RETRIES = 4


class LlmError(RuntimeError):
    pass


def _post(payload: dict) -> dict:
    last: Exception | None = None
    for attempt in range(MAX_RETRIES):
        try:
            r = httpx.post(
                f"{BASE_URL}/v1/chat/completions", json=payload, timeout=TIMEOUT
            )
            r.raise_for_status()
            return r.json()
        except Exception as e:  # noqa: BLE001 — network, 5xx, timeout, bad JSON
            last = e
            if attempt < MAX_RETRIES - 1:
                back = 2**attempt
                print(f"    llm retry {attempt + 1}/{MAX_RETRIES - 1} in {back}s ({e})")
                time.sleep(back)
    raise LlmError(f"llama-server failed after {MAX_RETRIES} attempts: {last}")


def chat_json(system: str, user: str, schema: dict, *, max_tokens: int = 4096,
              temperature: float = 0.4) -> dict:
    """One schema-constrained call. Returns the parsed JSON object.

    `temperature` is deliberately non-zero: at build time we *want* variety across
    the ~80 candidate questions we over-generate, and the schema — not greedy
    decoding — is what guarantees structure. (On-device the app must stay greedy;
    ADR-003 found a small model collapses without it. An 8B under a schema does not.)
    """
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": temperature,
        "max_tokens": max_tokens,
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": "response", "strict": True, "schema": schema},
        },
        # Qwen3 ships a thinking mode; it wastes tokens and can leak into the JSON.
        "chat_template_kwargs": {"enable_thinking": False},
    }
    data = _post(payload)
    text = data["choices"][0]["message"]["content"]
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise LlmError(f"model returned non-JSON despite schema: {text[:300]!r}") from e


def health() -> str:
    """Fail fast with a clear message if the server isn't up."""
    try:
        r = httpx.get(f"{BASE_URL}/v1/models", timeout=10)
        r.raise_for_status()
        return r.json()["data"][0]["id"]
    except Exception as e:  # noqa: BLE001
        raise LlmError(
            f"no llama-server at {BASE_URL} ({e}).\n"
            f"Start it with:  bash scripts/setup-genserver.sh --serve"
        ) from e
