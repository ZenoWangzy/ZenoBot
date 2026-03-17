#!/usr/bin/env bash
set -euo pipefail

TASK_NAME="$1"
PID="$2"
OUTPUT_FILE="$3"
EXIT_FILE="$4"
TIMEOUT_MIN="${5:-30}"
STALL_MIN="${6:-8}"
# New parameters for state convergence
RUN_DIR="${7:-}"
RUN_META="${8:-}"
LATEST_FILE="${9:-}"

BASE_DIR="${HOME}/.openclaw/workspace/claude-code-dispatch-macos"
DATA_DIR="${BASE_DIR}/data"
QUEUE_DIR="${DATA_DIR}/queue"

NOTIFY_BIN="${HOME}/.claude/hooks/notify-openclaw-event.sh"
NOTIFY_HOOK="${BASE_DIR}/scripts/hooks/notify.sh"
PROGRESS_INTERVAL_SEC="${CC_PROGRESS_INTERVAL_SEC:-300}"
MAX_RETRIES="${CC_MAX_RETRIES:-3}"

# Load enhanced notification functions if available
if [[ -f "$NOTIFY_HOOK" ]]; then
  # shellcheck source=hooks/notify.sh
  source "$NOTIFY_HOOK"
fi

start_ts=$(date +%s)
last_notify_api_err=0
last_notify_progress=$start_ts

notify() {
  local evt="$1"
  local detail="$2"
  if [[ -x "$NOTIFY_BIN" ]]; then
    "$NOTIFY_BIN" "$evt" "$detail" || true
  fi
}

# === Sanitize exit code to ensure it's a valid integer ===
# Returns 1 if empty or non-numeric
sanitize_exit_code() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    echo 1
    return
  fi
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo 1
  fi
}

# === Get retry count from meta.json (persisted) ===
get_retry_count() {
  if [[ -n "$RUN_META" ]] && [[ -f "$RUN_META" ]]; then
    local count=$(jq -r '.retry_count // 0' "$RUN_META" 2>/dev/null || echo 0)
    echo "$count"
  else
    echo 0
  fi
}

# === Increment and persist retry count to meta.json ===
increment_retry_count() {
  if [[ -n "$RUN_META" ]] && [[ -f "$RUN_META" ]]; then
    local current=$(get_retry_count)
    local new_count=$((current + 1))
    local tmp_meta="${RUN_META}.tmp"
    jq --argjson count "$new_count" '.retry_count=$count' "$RUN_META" > "$tmp_meta" && mv "$tmp_meta" "$RUN_META"
    echo "$new_count"
  else
    echo 1
  fi
}

# Write final status to per-run meta and latest.json
write_final_status() {
  local status="$1"
  local exit_code="$2"
  local reason="${3:-}"

  # Sanitize exit_code to ensure it's a valid integer
  local safe_exit_code=$(sanitize_exit_code "$exit_code")

  if [[ -n "$RUN_META" ]] && [[ -f "$RUN_META" ]]; then
    local tmp_meta="${RUN_META}.tmp"
    if [[ -n "$reason" ]]; then
      jq --arg status "$status" --argjson exit_code "$safe_exit_code" --arg reason "$reason" \
        '.status=$status | .exit_code=$exit_code | .end_reason=$reason' \
        "$RUN_META" > "$tmp_meta" && mv "$tmp_meta" "$RUN_META"
    else
      jq --arg status "$status" --argjson exit_code "$safe_exit_code" \
        '.status=$status | .exit_code=$exit_code' \
        "$RUN_META" > "$tmp_meta" && mv "$tmp_meta" "$RUN_META"
    fi
  fi

  if [[ -n "$LATEST_FILE" ]]; then
    local tmp_latest="${LATEST_FILE}.tmp"
    jq -n \
      --arg run_id "${RUN_DIR##*/}" \
      --arg task "$TASK_NAME" \
      --arg status "$status" \
      --argjson exit_code "$safe_exit_code" \
      --arg ts "$(date -Iseconds)" \
      '{current_run_id:$run_id,task_name:$task,status:$status,exit_code:$exit_code,updated_at:$ts}' \
      > "$tmp_latest" && mv "$tmp_latest" "$LATEST_FILE"
  fi
}

# Check if error is retryable
is_retryable_error() {
  if [[ -f "$OUTPUT_FILE" ]]; then
    if grep -Eiq "429|rate.?limit|timed out|ECONNREFUSED|ENOTFOUND|503|502|temporary" "$OUTPUT_FILE"; then
      return 0
    fi
  fi
  return 1
}

# Create retry task in queue (uses correct queue path)
create_retry_task() {
  local run_dir="$1"
  local orig_meta="$2"

  if [[ -z "$run_dir" ]] || [[ ! -f "$orig_meta" ]]; then
    return 1
  fi

  # Read original task params
  local prompt workdir callback_channel callback_target
  prompt=$(jq -r '.prompt // ""' "$orig_meta")
  workdir=$(jq -r '.workdir // ""' "$orig_meta")
  callback_channel=$(jq -r '.callback.channel // "discord"' "$orig_meta")
  callback_target=$(jq -r '.callback.target // ""' "$orig_meta")

  # Get current retry count from meta and increment
  local new_retry_count=$(increment_retry_count)

  # Create retry queue entry with CORRECT path: data/queue/ (not data/runs/queue/)
  local retry_run_id="retry-$(date +%s)-${TASK_NAME}"
  mkdir -p "$QUEUE_DIR"
  local queue_file="${QUEUE_DIR}/${retry_run_id}.json"

  jq -n \
    --arg orig_run "${run_dir##*/}" \
    --arg retry_run "$retry_run_id" \
    --arg task "$TASK_NAME" \
    --arg prompt "$prompt" \
    --arg wd "$workdir" \
    --arg ch "$callback_channel" \
    --arg tg "$callback_target" \
    --argjson retry_count "$new_retry_count" \
    '{original_run_id:$orig_run,retry_run_id:$retry_run,task_name:$task,prompt:$prompt,workdir:$wd,callback:{channel:$ch,target:$tg},retry_count:$retry_count,queued_at:now|strftime("%Y-%m-%dT%H:%M:%S%z")}' \
    > "$queue_file"

  return 0
}

while true; do
  now=$(date +%s)
  elapsed=$((now - start_ts))

  # timeout guard
  if (( elapsed > TIMEOUT_MIN * 60 )); then
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null || true
      sleep 1
      kill -9 "$PID" 2>/dev/null || true
    fi
    notify "cc_timeout" "task=${TASK_NAME} pid=${PID} elapsed=${elapsed}s"
    write_final_status "timeout" 124 "exceeded ${TIMEOUT_MIN}m limit"
    exit 0
  fi

  # process exited => check exit code and write final status
  if ! kill -0 "$PID" 2>/dev/null; then
    ec=1
    if [[ -f "$EXIT_FILE" ]] && [[ -s "$EXIT_FILE" ]]; then
      raw_ec=$(cat "$EXIT_FILE" 2>/dev/null || echo 1)
      ec=$(sanitize_exit_code "$raw_ec")
    fi

    final_status="failed"
    if [[ "$ec" == "0" ]]; then
      final_status="done"
      notify "cc_done" "task=${TASK_NAME} exit=0"
      # Send enhanced completion notification
      if declare -f notify_complete &>/dev/null; then
        run_id=""
        if [[ -n "$RUN_DIR" ]]; then
          run_id="${RUN_DIR##*/}"
        fi
        notify_complete "$run_id" "Task completed successfully"
      fi
    else
      notify "cc_exit_nonzero" "task=${TASK_NAME} exit=${ec}"
      # Send enhanced failure notification
      if declare -f notify_failure &>/dev/null; then
        run_id=""
        if [[ -n "$RUN_DIR" ]]; then
          run_id="${RUN_DIR##*/}"
        fi
        # Get last 20 lines of output for error summary
        error_summary=""
        if [[ -f "$OUTPUT_FILE" ]]; then
          error_summary=$(tail -n 20 "$OUTPUT_FILE" 2>/dev/null || echo "")
        fi
        notify_failure "$run_id" "$ec" "$error_summary"
      fi

      # Auto-retry for retryable errors (if enabled and under max retries)
      if [[ "$MAX_RETRIES" -gt 0 ]] && is_retryable_error; then
        local_retry_count=$(get_retry_count)
        if [[ $local_retry_count -lt $MAX_RETRIES ]]; then
          notify "cc_retry" "task=${TASK_NAME} creating retry task (attempt $((local_retry_count + 1))/$MAX_RETRIES)"
          create_retry_task "$RUN_DIR" "$RUN_META" || true
        fi
      fi
    fi

    write_final_status "$final_status" "$ec"
    exit 0
  fi

  # stall guard based on output mtime
  if [[ -f "$OUTPUT_FILE" ]]; then
    if stat -f %m "$OUTPUT_FILE" >/dev/null 2>&1; then
      mtime=$(stat -f %m "$OUTPUT_FILE")
    else
      mtime=$(stat -c %Y "$OUTPUT_FILE")
    fi
    idle=$((now - mtime))
    if (( idle > STALL_MIN * 60 )); then
      notify "cc_stall" "task=${TASK_NAME} idle=${idle}s"
      # Update meta with stall status but don't exit
      if [[ -n "$RUN_META" ]] && [[ -f "$RUN_META" ]]; then
        tmp_meta="${RUN_META}.tmp"
        jq --argjson idle "$idle" '.stall_detected=true | .stall_idle_seconds=$idle' "$RUN_META" > "$tmp_meta" && mv "$tmp_meta" "$RUN_META"
      fi
      # don't spam; extend threshold window by bumping mtime reference via touch marker
      touch "$OUTPUT_FILE".watchdog-heartbeat 2>/dev/null || true
      sleep 60
    fi
  fi

  # API/network error pattern guard (best effort, notify at most once per 5 min)
  if [[ -f "$OUTPUT_FILE" ]]; then
    if grep -Eiq "unable to connect|timed out|timeout|ECONN|ENOTFOUND|429|5[0-9]{2}|api error|fetch failed" "$OUTPUT_FILE"; then
      if (( now - last_notify_api_err > 300 )); then
        last_notify_api_err=$now
        notify "cc_api_error" "task=${TASK_NAME} detected_in_output=1"
      fi
    fi
  fi

  # periodic heartbeat status (default every 5 min)
  if (( PROGRESS_INTERVAL_SEC > 0 )) && (( now - last_notify_progress >= PROGRESS_INTERVAL_SEC )); then
    last_notify_progress=$now
    idle_s="na"
    if [[ -f "$OUTPUT_FILE" ]]; then
      if stat -f %m "$OUTPUT_FILE" >/dev/null 2>&1; then
        mtime=$(stat -f %m "$OUTPUT_FILE")
      else
        mtime=$(stat -c %Y "$OUTPUT_FILE")
      fi
      idle_s=$((now - mtime))
    fi
    notify "cc_progress" "task=${TASK_NAME} pid=${PID} elapsed=${elapsed}s idle=${idle_s}s"

    # Send enhanced progress notification
    if declare -f notify_progress &>/dev/null; then
      run_id=""
      if [[ -n "$RUN_DIR" ]]; then
        run_id="${RUN_DIR##*/}"
      fi
      notify_progress "$run_id" "Task in progress: elapsed=${elapsed}s, idle=${idle_s}s"
    fi

    # Update meta with progress heartbeat and notification flag
    if [[ -n "$RUN_META" ]] && [[ -f "$RUN_META" ]]; then
      tmp_meta="${RUN_META}.tmp"
      jq --argjson elapsed "$elapsed" --argjson idle "$idle_s" --argjson now_ts "$now" \
        '.progress_heartbeat=now | .elapsed_seconds=$elapsed | .idle_seconds=$idle | .notify.last_progress_at=$now_ts' \
        "$RUN_META" > "$tmp_meta" && mv "$tmp_meta" "$RUN_META"
    fi
  fi

  sleep 20
done
