#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python scripts/validation/validate_repository.py
bash -n scripts/*.sh
python -m compileall -q pipeline/src
(
  cd pipeline
  PYTHONPATH=. pytest -q tests
)

cat <<'MESSAGE'
Static and pipeline validation passed.
Flutter package resolution, analysis, tests, Android compilation, model inference,
and physical-camera OMR validation still require the pinned Flutter/Android toolchain
and target devices.
MESSAGE
