#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/.openclaw/workspace/claude-code-dispatch-macos"
DATA_DIR="${BASE_DIR}/data"
QUEUE_DIR="${DATA_DIR}/queue"
RUNNING_DIR="${DATA_DIR}/running"
DONE_DIR="${DATA_DIR}/done"
LATEST_FILE="${DATA_DIR}/latest.json"
META_FILE="${DATA_DIR}/task-meta.json"

q_count=$(find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
r_count=$(find "$RUNNING_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
d_count=$(find "$DONE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')

printf 'CC Queue Status\n'
printf 'queued=%s running=%s done=%s\n' "$q_count" "$r_count" "$d_count"

if [[ -f "$META_FILE" ]]; then
  echo "-- meta --"
  jq '{task_name,status,run_id,worker_id,started_at,finished_at,exit_code}' "$META_FILE" 2>/dev/null || cat "$META_FILE"
fi

if [[ -f "$LATEST_FILE" ]]; then
  echo "-- latest --"
  jq '{task_name,status,event,timestamp,run_id,worker_id,callback}' "$LATEST_FILE" 2>/dev/null || cat "$LATEST_FILE"
fi

echo "-- running files --"
ls -1 "$RUNNING_DIR" 2>/dev/null || true

echo "-- queued files --"
ls -1 "$QUEUE_DIR" 2>/dev/null || true
