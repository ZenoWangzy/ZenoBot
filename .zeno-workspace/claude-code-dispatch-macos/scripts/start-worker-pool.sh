#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/.openclaw/workspace/claude-code-dispatch-macos"
WORKER_SCRIPT="${BASE_DIR}/scripts/worker-claude-queue.sh"
N="${1:-2}"

pkill -f 'worker-claude-queue.sh' 2>/dev/null || true
sleep 1

for i in $(seq 1 "$N"); do
  WORKER_ID="w${i}" nohup bash "$WORKER_SCRIPT" >"${BASE_DIR}/data/worker-w${i}.log" 2>&1 &
  echo "started worker w${i} pid=$!"
done
