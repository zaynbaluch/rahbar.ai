#!/usr/bin/env bash
# Supervises the whole unattended content build (ADR-008): keeps llama-server alive,
# resumes generation until every topic is done, then packs it and reinstalls the app.
#
#   bash scripts/run-content-build.sh
#
# Why a supervisor and not just `gen_content`: the run takes ~8 h and llama-server has
# been OOM-killed once already (host RAM, not VRAM — a Gradle daemon pushed a 14 GB box
# over while the 5 GB model was mapped). Generation is checkpointed per (stage, topic), so
# a kill costs at most one topic; the only thing missing was something to notice and
# restart. That is this.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO/data/processed/content/build.log"
mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1

MAX_ROUNDS="${MAX_ROUNDS:-40}"

server_up() { curl -s -m 5 http://127.0.0.1:8080/v1/models > /dev/null 2>&1; }

start_server() {
  echo "--- starting llama-server $(date +%H:%M:%S)"
  setsid nohup bash "$REPO/scripts/setup-genserver.sh" --serve < /dev/null \
    >> "$REPO/data/processed/content/server.log" 2>&1 &
  for _ in $(seq 1 60); do
    sleep 5
    if server_up; then
      # Make the model server a *less* attractive OOM victim than the browser/IDE that
      # actually caused the pressure. (Positive adjustments need no privileges.)
      for pid in $(pgrep -x llama-server); do echo 0 > "/proc/$pid/oom_score_adj" 2>/dev/null; done
      echo "--- server up $(date +%H:%M:%S)"
      return 0
    fi
  done
  echo "!!! server failed to come up"
  return 1
}

remaining() {
  cd "$REPO/pipeline" || exit 1
  # Match only the progress line ("→ plan_verify  5/88 done") — the header also contains
  # the word plan_verify, and matching both returns two numbers instead of one.
  uv run python -m src.gen_content --dry-run 2>/dev/null \
    | awk '/plan_verify[ \t]+[0-9]+\/[0-9]+/ {split($3,a,"/"); print a[2]-a[1]; exit}'
}

echo "=== content build started $(date) ==="

for round in $(seq 1 "$MAX_ROUNDS"); do
  left="$(remaining)"
  echo "=== round $round · $left topics left · $(date +%H:%M:%S)"
  [ -z "$left" ] && { echo "!!! could not read progress"; break; }
  [ "$left" -eq 0 ] && { echo "=== all topics complete"; break; }

  server_up || start_server || { sleep 60; continue; }

  cd "$REPO/pipeline" || exit 1
  uv run python -m src.gen_content            # resumes; exits if the server dies
  echo "--- gen_content exited ($?) $(date +%H:%M:%S)"
  sleep 5
done

# --- pack + ship ---
cd "$REPO/pipeline" || exit 1
uv run python -m src.build_content_db

# Free the GPU + the model's page cache before Gradle runs: a Java daemon next to a mapped
# 5 GB model is exactly what triggered the OOM in the first place.
pkill -x llama-server
sleep 3

cd "$REPO/app" || exit 1
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk

echo "=== ALL DONE $(date) ==="
