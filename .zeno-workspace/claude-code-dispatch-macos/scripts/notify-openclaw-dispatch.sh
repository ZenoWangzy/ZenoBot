#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/.openclaw/workspace/claude-code-dispatch-macos"
DATA_DIR="${BASE_DIR}/data"
RUNS_DIR="${DATA_DIR}/runs"
LOG_FILE="${DATA_DIR}/hook.log"
LATEST_FILE="${DATA_DIR}/latest.json"
LOCK_FILE="${DATA_DIR}/.hook-lock"
NOTIFY_STATE_FILE="${DATA_DIR}/.last-notify-key"
OPENCLAW_BIN="${OPENCLAW_BIN:-/Users/ZenoWang/.npm-global/bin/openclaw}"
OPENCLAW_CONFIG="${HOME}/.openclaw/openclaw.json"
DEFAULT_CALLBACK_TARGET="853303202236858379"

mkdir -p "${DATA_DIR}"
log(){ printf '[%s] %s\n' "$(date -Iseconds)" "$*" >>"${LOG_FILE}"; }

get_mtime(){
  local f="$1"
  if stat -f %m "$f" >/dev/null 2>&1; then
    stat -f %m "$f"
  else
    stat -c %Y "$f"
  fi
}

# === Dual-Condition Completion Check ===
# Returns 0 (true) if task is complete, 1 (false) otherwise
# Sets COMPLETION_REASON to indicate which condition was met
COMPLETION_REASON=""
is_task_complete() {
  local run_dir="$1"
  local required_output="$2"
  local workdir="$3"

  COMPLETION_REASON=""

  # Condition 1: exit_code is persisted and has value
  local exit_file="${run_dir}/exit-code.txt"
  if [[ -f "$exit_file" ]] && [[ -s "$exit_file" ]]; then
    COMPLETION_REASON="exit_code"
    return 0
  fi

  # Condition 2: required_output exists and is non-empty
  if [[ -n "$required_output" ]]; then
    # Handle multiple paths (colon-separated)
    IFS=':' read -ra paths <<< "$required_output"
    for raw_path in "${paths[@]}"; do
      # Resolve relative paths against workdir
      local resolved_path="$raw_path"
      if [[ -n "$workdir" ]] && [[ "$raw_path" != /* ]]; then
        resolved_path="${workdir}/${raw_path}"
      fi

      if [[ -f "$resolved_path" ]] && [[ -s "$resolved_path" ]]; then
        COMPLETION_REASON="required_output"
        return 0
      fi
    done
  fi

  return 1
}

log "=== Hook fired ==="

INPUT=""
if [ ! -t 0 ] && [ -e /dev/stdin ]; then
  if command -v timeout >/dev/null 2>&1; then
    INPUT=$(timeout 2 cat /dev/stdin 2>/dev/null || true)
  elif command -v gtimeout >/dev/null 2>&1; then
    INPUT=$(gtimeout 2 cat /dev/stdin 2>/dev/null || true)
  else
    INPUT=$(cat /dev/stdin 2>/dev/null || true)
  fi
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# only notify on terminal events
if [[ "$EVENT" != "Stop" && "$EVENT" != "SessionEnd" ]]; then
  log "Skip non-terminal event: $EVENT"
  exit 0
fi

# dedupe (Stop + SessionEnd)
if [ -f "$LOCK_FILE" ]; then
  NOW=$(date +%s)
  MTIME=$(get_mtime "$LOCK_FILE" || echo 0)
  AGE=$((NOW - MTIME))
  if [ "$AGE" -lt 30 ]; then
    log "Duplicate hook in ${AGE}s; skip"
    exit 0
  fi
fi
touch "$LOCK_FILE"

# === Read from per-run directory (primary) or legacy files (fallback) ===
RUN_ID=""
TASK_NAME="unknown"
CALLBACK_CHANNEL="discord"
CALLBACK_TARGET=""
CALLBACK_ACCOUNT=""
REQUIRED_OUTPUT=""
RUN_DIR=""
RUN_META=""
EXIT_CODE=""
TASK_STATUS="running"

# Try to read from latest.json first
if [ -f "$LATEST_FILE" ]; then
  RUN_ID=$(jq -r '.current_run_id // ""' "$LATEST_FILE" 2>/dev/null || echo "")
  TASK_NAME=$(jq -r '.task_name // "unknown"' "$LATEST_FILE" 2>/dev/null || echo "unknown")
  TASK_STATUS=$(jq -r '.status // "running"' "$LATEST_FILE" 2>/dev/null || echo "running")
fi

# If we have a run_id, read from per-run directory
WORKDIR=""
if [ -n "$RUN_ID" ]; then
  RUN_DIR="${RUNS_DIR}/${RUN_ID}"
  RUN_META="${RUN_DIR}/meta.json"
  if [ -f "$RUN_META" ]; then
    TASK_NAME=$(jq -r '.task_name // "unknown"' "$RUN_META" 2>/dev/null || echo "unknown")
    WORKDIR=$(jq -r '.workdir // ""' "$RUN_META" 2>/dev/null || echo "")
    CALLBACK_CHANNEL=$(jq -r '.callback.channel // "discord"' "$RUN_META" 2>/dev/null || echo "discord")
    CALLBACK_TARGET=$(jq -r '.callback.target // ""' "$RUN_META" 2>/dev/null || echo "")
    CALLBACK_ACCOUNT=$(jq -r '.callback.account // ""' "$RUN_META" 2>/dev/null || echo "")
    REQUIRED_OUTPUT=$(jq -r '.required_output // ""' "$RUN_META" 2>/dev/null || echo "")
    EXIT_CODE=$(jq -r '.exit_code // ""' "$RUN_META" 2>/dev/null || echo "")
    TASK_STATUS=$(jq -r '.status // "running"' "$RUN_META" 2>/dev/null || echo "running")
  fi
else
  # Fallback to legacy global files
  LEGACY_META="${DATA_DIR}/task-meta.json"
  if [ -f "$LEGACY_META" ]; then
    TASK_NAME=$(jq -r '.task_name // "unknown"' "$LEGACY_META" 2>/dev/null || echo "unknown")
    CALLBACK_CHANNEL=$(jq -r '.callback.channel // "discord"' "$LEGACY_META" 2>/dev/null || echo "discord")
    CALLBACK_TARGET=$(jq -r '.callback.target // ""' "$LEGACY_META" 2>/dev/null || echo "")
    CALLBACK_ACCOUNT=$(jq -r '.callback.account // ""' "$LEGACY_META" 2>/dev/null || echo "")
    EXIT_CODE=$(jq -r '.exit_code // ""' "$LEGACY_META" 2>/dev/null || echo "")
  fi
fi

# fallback routing to owner when callback target is missing
if [ -z "${CALLBACK_TARGET// }" ]; then
  CALLBACK_TARGET="$DEFAULT_CALLBACK_TARGET"
fi

# Read output from per-run or legacy
OUTPUT=""
if [ -n "$RUN_DIR" ] && [ -f "${RUN_DIR}/output.txt" ]; then
  OUTPUT=$(tail -c 5000 "${RUN_DIR}/output.txt")
elif [ -s "${DATA_DIR}/task-output.txt" ]; then
  OUTPUT=$(tail -c 5000 "${DATA_DIR}/task-output.txt")
elif [ -s /tmp/claude-code-output.txt ]; then
  OUTPUT=$(tail -c 5000 /tmp/claude-code-output.txt)
elif [ -n "$CWD" ] && [ -d "$CWD" ]; then
  OUTPUT="No stdout captured. cwd=${CWD}"
fi

# === Dual-Condition Completion Check ===
# Only update status if task is truly complete
IS_COMPLETE=0
if [ -n "$RUN_DIR" ]; then
  if is_task_complete "$RUN_DIR" "$REQUIRED_OUTPUT" "$WORKDIR"; then
    IS_COMPLETE=1
    log "Task complete confirmed via ${COMPLETION_REASON}"
  else
    log "Task not yet complete (no exit_code or required_output found)"
  fi
fi

# Update latest.json only if task is complete OR if status was already set by watchdog
# Hook no longer writes status:done directly - that's watchdog's job
if [ "$IS_COMPLETE" -eq 1 ]; then
  # Verify watchdog already set status, or set it now as fallback
  if [ "$TASK_STATUS" = "running" ]; then
    # Watchdog hasn't updated yet - this shouldn't happen but handle gracefully
    log "Warning: Hook detected completion but watchdog hasn't updated status"

    # Determine status based on completion reason
    if [ "$COMPLETION_REASON" = "required_output" ]; then
      # required_output satisfied without exit_code -> done (not failed!)
      TASK_STATUS="done"
      EXIT_CODE="0"
      log "Task marked done via required_output (no exit_code yet)"
    else
      # exit_code path - read from file
      if [ -f "${RUN_DIR}/exit-code.txt" ]; then
        EXIT_CODE=$(cat "${RUN_DIR}/exit-code.txt" 2>/dev/null || echo "1")
      fi
      # Sanitize exit_code
      if [[ ! "$EXIT_CODE" =~ ^[0-9]+$ ]]; then
        EXIT_CODE="1"
      fi
      if [ "$EXIT_CODE" = "0" ]; then
        TASK_STATUS="done"
      else
        TASK_STATUS="failed"
      fi
    fi
  fi
fi

# Write latest.json with current state (don't override watchdog's status)
if [ -n "$RUN_ID" ]; then
  jq -n \
    --arg run_id "$RUN_ID" \
    --arg sid "$SESSION_ID" \
    --arg ts "$(date -Iseconds)" \
    --arg event "$EVENT" \
    --arg cwd "$CWD" \
    --arg task "$TASK_NAME" \
    --arg channel "$CALLBACK_CHANNEL" \
    --arg target "$CALLBACK_TARGET" \
    --arg status "$TASK_STATUS" \
    --arg exit "$EXIT_CODE" \
    --arg output "$OUTPUT" \
    '{current_run_id:$run_id,session_id:$sid,timestamp:$ts,event:$event,cwd:$cwd,task_name:$task,callback:{channel:$channel,target:$target},status:$status,exit_code:$exit,output:$output}' >"$LATEST_FILE"
fi

SUMMARY=$(printf '%s' "$OUTPUT" | tr '\n' ' ' | tail -c 900)

# Build notification message based on completion status
if [ "$IS_COMPLETE" -eq 1 ]; then
  if [ "$EXIT_CODE" = "0" ]; then
    MSG="✅ Claude Code任务完成\n任务: ${TASK_NAME}\n事件: ${EVENT}\nrun_id: ${RUN_ID}\nexit: ${EXIT_CODE}\n结果文件: ${LATEST_FILE}\n摘要:\n${SUMMARY}"
  else
    MSG="❌ Claude Code任务失败\n任务: ${TASK_NAME}\n事件: ${EVENT}\nrun_id: ${RUN_ID}\nexit: ${EXIT_CODE}\n结果文件: ${LATEST_FILE}\n摘要:\n${SUMMARY}"
  fi
else
  MSG="⏳ Claude Code会话结束（等待完成确认）\n任务: ${TASK_NAME}\n事件: ${EVENT}\nrun_id: ${RUN_ID}\n状态: ${TASK_STATUS}\n摘要:\n${SUMMARY}"
fi

# dedupe by task+event+run_id+exit_code+output hash
OUT_HASH=$(printf '%s' "$SUMMARY" | shasum | awk '{print $1}')
NOTIFY_KEY="${TASK_NAME}|${EVENT}|${RUN_ID}|${EXIT_CODE}|${OUT_HASH}"
if [[ -f "$NOTIFY_STATE_FILE" ]] && [[ "$(cat "$NOTIFY_STATE_FILE" 2>/dev/null || true)" == "$NOTIFY_KEY" ]]; then
  log "Duplicate notify key; skip send"
  exit 0
fi
printf '%s' "$NOTIFY_KEY" > "$NOTIFY_STATE_FILE"

# direct channel callback (Discord preferred)
if [ -n "$CALLBACK_TARGET" ] && [ -x "$OPENCLAW_BIN" ]; then
  if [ -n "$CALLBACK_ACCOUNT" ]; then
    "$OPENCLAW_BIN" message send --channel "$CALLBACK_CHANNEL" --account "$CALLBACK_ACCOUNT" --target "$CALLBACK_TARGET" --message "$MSG" >/dev/null 2>&1 || true
  else
    "$OPENCLAW_BIN" message send --channel "$CALLBACK_CHANNEL" --target "$CALLBACK_TARGET" --message "$MSG" >/dev/null 2>&1 || true
  fi
fi

# wake supervisor via gateway API (best effort)
if [ -f "$OPENCLAW_CONFIG" ]; then
  TOKEN=$(jq -r '.gateway.auth.token // empty' "$OPENCLAW_CONFIG" 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then
    curl -sS -X POST "http://127.0.0.1:18789/api/cron/wake" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"Claude Code任务事件：${TASK_NAME} (status=${TASK_STATUS})\",\"mode\":\"now\"}" >/dev/null 2>&1 || true
  fi
fi

log "Hook done task=${TASK_NAME} event=${EVENT} status=${TASK_STATUS} complete=${IS_COMPLETE}"
exit 0
