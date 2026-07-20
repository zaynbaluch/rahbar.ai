#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

check_command() {
  local command="$1"
  if command -v "$command" >/dev/null 2>&1; then
    printf 'OK   %-14s %s\n' "$command" "$(command -v "$command")"
  else
    printf 'MISS %-14s\n' "$command"
    status=1
  fi
}

for command in git java keytool flutter dart adb sdkmanager cmake; do
  check_command "$command"
done

[[ -d "$REPO_ROOT/third_party/llama_cpp_dart" ]] \
  && echo "OK   llama_cpp_dart" \
  || { echo "MISS llama_cpp_dart (run scripts/setup-llama.sh)"; status=1; }

[[ -f "$REPO_ROOT/app/assets/rag/curriculum.db" ]] \
  && echo "OK   curriculum.db" \
  || { echo "MISS curriculum.db"; status=1; }

[[ -f "$REPO_ROOT/app/assets/content/content_pack.db" ]] \
  && echo "OK   content_pack.db" \
  || { echo "MISS content_pack.db"; status=1; }

exit "$status"
