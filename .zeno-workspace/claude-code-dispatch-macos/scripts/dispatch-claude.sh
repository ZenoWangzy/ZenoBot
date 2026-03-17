#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/.openclaw/workspace/claude-code-dispatch-macos"
DATA_DIR="${BASE_DIR}/data"
RUNS_DIR="${DATA_DIR}/runs"
LATEST_FILE="${DATA_DIR}/latest.json"
LEGACY_META="${DATA_DIR}/task-meta.json"
LEGACY_OUTPUT="${DATA_DIR}/task-output.txt"
LEGACY_EXIT="${DATA_DIR}/task-exit-code.txt"
WATCHDOG_SCRIPT="${BASE_DIR}/scripts/watch-cc-task.sh"
CLAUDE_BIN_DEFAULT="${HOME}/.local/bin/claude"

mkdir -p "$DATA_DIR" "$RUNS_DIR"

PROMPT=""
TASK_NAME="adhoc-$(date +%s)"
WORKDIR="$(pwd)"
CALLBACK_CHANNEL="discord"
CALLBACK_TARGET="853303202236858379"
CALLBACK_ACCOUNT=""
PERMISSION_MODE="bypassPermissions"
ALLOWED_TOOLS=""
AGENT_TEAMS=0
TEAMMATE_MODE="auto"
MODEL=""
CLAUDE_BIN="${CLAUDE_BIN:-$CLAUDE_BIN_DEFAULT}"
TIMEOUT_MIN="${CC_TIMEOUT_MIN:-30}"
STALL_MIN="${CC_STALL_MIN:-8}"
REQUIRED_OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prompt) PROMPT="$2"; shift 2;;
    -n|--name) TASK_NAME="$2"; shift 2;;
    -w|--workdir) WORKDIR="$2"; shift 2;;
    --channel) CALLBACK_CHANNEL="$2"; shift 2;;
    --target) CALLBACK_TARGET="$2"; shift 2;;
    --account) CALLBACK_ACCOUNT="$2"; shift 2;;
    --permission-mode) PERMISSION_MODE="$2"; shift 2;;
    --allowed-tools) ALLOWED_TOOLS="$2"; shift 2;;
    --agent-teams) AGENT_TEAMS=1; shift;;
    --teammate-mode) TEAMMATE_MODE="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --claude-bin) CLAUDE_BIN="$2"; shift 2;;
    --timeout-min) TIMEOUT_MIN="$2"; shift 2;;
    --stall-min) STALL_MIN="$2"; shift 2;;
    --required-output) REQUIRED_OUTPUT="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if [[ -z "$PROMPT" ]]; then
  echo "--prompt is required"
  exit 1
fi

if [[ ! -x "$CLAUDE_BIN" ]]; then
  if command -v claude >/dev/null 2>&1; then
    CLAUDE_BIN="$(command -v claude)"
  else
    echo "Claude binary not found. expected: $CLAUDE_BIN"
    exit 1
  fi
fi

# === Per-Run Isolation ===
# Generate unique run_id: timestamp-sanitized-task-name
SANITIZED_NAME=$(printf '%s' "$TASK_NAME" | tr -c '[:alnum:]-' '-' | sed 's/--*/-/g; s/^-\|-$//g')
RUN_ID="$(date +%s)-${SANITIZED_NAME}"
RUN_DIR="${RUNS_DIR}/${RUN_ID}"

# Create per-run directory
mkdir -p "$RUN_DIR"

# Per-run file paths
RUN_META="${RUN_DIR}/meta.json"
RUN_OUTPUT="${RUN_DIR}/output.txt"
RUN_EXIT="${RUN_DIR}/exit-code.txt"

# Write per-run meta.json (enhanced with notification tracking)
jq -n \
  --arg run_id "$RUN_ID" \
  --arg task "$TASK_NAME" \
  --arg prompt "$PROMPT" \
  --arg wd "$WORKDIR" \
  --arg ts "$(date -Iseconds)" \
  --arg ch "$CALLBACK_CHANNEL" \
  --arg tg "$CALLBACK_TARGET" \
  --arg acc "$CALLBACK_ACCOUNT" \
  --arg req_out "$REQUIRED_OUTPUT" \
  '{
    run_id:$run_id,
    task_name:$task,
    prompt:$prompt,
    workdir:$wd,
    started_at:$ts,
    callback:{channel:$ch,target:$tg,account:$acc},
    required_output:$req_out,
    status:"running",
    exit_code:null,
    notify:{
      start_sent:false,
      last_progress_at:0,
      completion_sent:false,
      failure_sent:false
    }
  }' > "$RUN_META"

# === Start Hook: Send start notification ===
NOTIFY_HOOK="${BASE_DIR}/scripts/hooks/notify.sh"
if [[ -f "$NOTIFY_HOOK" ]]; then
  # shellcheck source=hooks/notify.sh
  source "$NOTIFY_HOOK"
  notify_start "$RUN_ID" "Task dispatched: $TASK_NAME"
  echo "Start notification sent"
fi

: > "$RUN_OUTPUT"
: > "$RUN_EXIT"

# Update latest.json to only store pointer
jq -n \
  --arg run_id "$RUN_ID" \
  --arg task "$TASK_NAME" \
  --arg ts "$(date -Iseconds)" \
  '{current_run_id:$run_id,task_name:$task,started_at:$ts,status:"running"}' > "$LATEST_FILE"

# === Backward Compatibility Layer ===
# Update legacy global files (for older consumers)
cp "$RUN_META" "$LEGACY_META"
ln -sf "$RUN_OUTPUT" "$LEGACY_OUTPUT" 2>/dev/null || cp "$RUN_OUTPUT" "$LEGACY_OUTPUT"
ln -sf "$RUN_EXIT" "$LEGACY_EXIT" 2>/dev/null || : > "$LEGACY_EXIT"

CMD=("$CLAUDE_BIN" -p "$PROMPT" --permission-mode "$PERMISSION_MODE")
if [[ -n "$ALLOWED_TOOLS" ]]; then
  CMD+=(--allowedTools "$ALLOWED_TOOLS")
fi
if [[ "$AGENT_TEAMS" -eq 1 ]]; then
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  CMD+=(--teammate-mode "$TEAMMATE_MODE")
fi
if [[ -n "$MODEL" ]]; then
  export ANTHROPIC_MODEL="$MODEL"
fi

echo "Dispatching Claude task: $TASK_NAME"
echo "Run ID: $RUN_ID"
echo "Run Dir: $RUN_DIR"
echo "Claude bin: $CLAUDE_BIN"
echo "Workdir: $WORKDIR"

nohup bash -lc "cd $(printf '%q' "$WORKDIR") && $(printf '%q ' "${CMD[@]}") 2>&1 | tee $(printf '%q' "$RUN_OUTPUT"); ec=\${PIPESTATUS[0]}; echo \$ec > $(printf '%q' "$RUN_EXIT"); exit \$ec" >/dev/null 2>&1 &
PID=$!

# Watchdog for timeout/stall/api-error/non-zero exit notifications
# Pass RUN_DIR for state convergence
if [[ -x "$WATCHDOG_SCRIPT" ]]; then
  nohup bash "$WATCHDOG_SCRIPT" "$TASK_NAME" "$PID" "$RUN_OUTPUT" "$RUN_EXIT" "$TIMEOUT_MIN" "$STALL_MIN" "$RUN_DIR" "$RUN_META" "$LATEST_FILE" >/dev/null 2>&1 &
fi

echo "Started PID=$PID"
echo "Meta: $RUN_META"
echo "Output: $RUN_OUTPUT"
echo "Exit: $RUN_EXIT"
echo "Watchdog: timeout=${TIMEOUT_MIN}m stall=${STALL_MIN}m"
