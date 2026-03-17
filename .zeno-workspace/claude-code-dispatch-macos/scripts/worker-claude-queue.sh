#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/.openclaw/workspace/claude-code-dispatch-macos"
DATA_DIR="${BASE_DIR}/data"
QUEUE_DIR="${DATA_DIR}/queue"
RUNNING_DIR="${DATA_DIR}/running"
DONE_DIR="${DATA_DIR}/done"
META_FILE="${DATA_DIR}/task-meta.json"
LATEST_FILE="${DATA_DIR}/latest.json"
TASK_OUTPUT="${DATA_DIR}/task-output.txt"
TASK_EXIT="${DATA_DIR}/task-exit-code.txt"
RUNNER="${BASE_DIR}/scripts/claude_code_run.py"
NOTIFY_BIN="${HOME}/.claude/hooks/notify-openclaw-event.sh"
WORKER_ID="${WORKER_ID:-w1}"
RUNS_DIR="${DATA_DIR}/runs"

mkdir -p "$QUEUE_DIR" "$RUNNING_DIR" "$DONE_DIR" "$RUNS_DIR"
chmod +x "$RUNNER" || true

for f in "$RUNNING_DIR"/*.json; do
  [[ -e "$f" ]] || break
  mv "$f" "$QUEUE_DIR/"
done

echo "[worker:${WORKER_ID}] started at $(date -Iseconds)"
while true; do
  next_file="$(find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.json' | sort | head -n 1 || true)"
  if [[ -z "$next_file" ]]; then
    sleep 2
    continue
  fi

  base="$(basename "$next_file")"
  running_file="${RUNNING_DIR}/${base}"
  if ! mv "$next_file" "$running_file" 2>/dev/null; then
    sleep 1
    continue
  fi

  run_id="${base%.json}"
  run_dir="${RUNS_DIR}/${run_id}"
  mkdir -p "$run_dir"
  run_output="${run_dir}/task-output.txt"
  run_exit="${run_dir}/task-exit-code.txt"
  run_meta="${run_dir}/meta.json"
  cp "$running_file" "$run_meta"

  TASK_NAME="$(jq -r '.task_name' "$running_file")"
  PROMPT="$(jq -r '.prompt' "$running_file")"
  WORKDIR="$(jq -r '.workdir' "$running_file")"
  CLAUDE_BIN="$(jq -r '.claude_bin' "$running_file")"
  PERMISSION_MODE="$(jq -r '.permission_mode' "$running_file")"
  ALLOWED_TOOLS="$(jq -r '.allowed_tools' "$running_file")"
  AGENT_TEAMS="$(jq -r '.agent_teams' "$running_file")"
  TEAMMATE_MODE="$(jq -r '.teammate_mode' "$running_file")"
  MODEL="$(jq -r '.model' "$running_file")"
  TIMEOUT_MIN="$(jq -r '.timeout_min // 20' "$running_file")"
  REQUIRED_OUTPUTS_JSON="$(jq -c 'if .required_outputs then .required_outputs elif .required_output then [ .required_output ] else [] end' "$running_file")"

  jq --arg ts "$(date -Iseconds)" '.status="running" | .started_at=$ts | .worker_id="'"$WORKER_ID"'" | .run_id="'"$run_id"'"' "$running_file" > "${running_file}.tmp" && mv "${running_file}.tmp" "$running_file"
  cp "$running_file" "$run_meta"
  jq -n --arg task "$TASK_NAME" --arg ts "$(date -Iseconds)" --arg run_id "$run_id" --arg worker "$WORKER_ID" '{task_name:$task,status:"running",started_at:$ts,run_id:$run_id,worker_id:$worker}' > "$META_FILE"

  : > "$TASK_OUTPUT"
  : > "$TASK_EXIT"
  : > "$run_output"
  : > "$run_exit"

  echo "[worker:${WORKER_ID}] running task=$TASK_NAME run_id=$run_id at $(date -Iseconds)"
  set +e
  SESSION_ID=$(jq -r '.session_id // ""' "$running_file")
  ROUND=$(jq -r '.round // 1' "$running_file")
  run_cmd=(python3 "$RUNNER" --claude-bin "$CLAUDE_BIN" --prompt "$PROMPT" --permission-mode "$PERMISSION_MODE" --workdir "$WORKDIR")
  [[ -n "$ALLOWED_TOOLS" ]] && run_cmd+=(--allowed-tools "$ALLOWED_TOOLS")
  # 多轮对话：Round 1用--session-id，Round 2+用--resume
  if [[ "$ROUND" -eq 1 ]] || [[ -z "$ROUND" ]]; then
    [[ -n "$SESSION_ID" ]] && run_cmd+=(--session-id "$SESSION_ID")
  else
    [[ -n "$SESSION_ID" ]] && run_cmd+=(--resume "$SESSION_ID")
  fi
  [[ -n "$TEAMMATE_MODE" ]] && run_cmd+=(--teammate-mode "$TEAMMATE_MODE")
  [[ -n "$MODEL" ]] && run_cmd+=(--model "$MODEL")
  [[ "$AGENT_TEAMS" == "1" ]] && run_cmd+=(--agent-teams)

  "${run_cmd[@]}" > >(tee "$TASK_OUTPUT" "$run_output") 2>&1 &
  job_pid=$!

  start_ts=$(date +%s)
  rc=""
  forced="0"

  while true; do
    now=$(date +%s)
    elapsed=$((now - start_ts))

    if [[ "$REQUIRED_OUTPUTS_JSON" != "[]" ]]; then
      all_ok=1
      while IFS= read -r ro; do
        [[ -n "$ro" ]] || continue
        if [[ ! -f "$WORKDIR/$ro" ]]; then
          all_ok=0
          break
        fi
      done < <(jq -r '.[]' <<<"$REQUIRED_OUTPUTS_JSON")

      if [[ "$all_ok" == "1" ]]; then
        echo "[worker:${WORKER_ID}] all required outputs detected: $REQUIRED_OUTPUTS_JSON" | tee -a "$TASK_OUTPUT" "$run_output" >/dev/null
        kill "$job_pid" 2>/dev/null || true
        sleep 1
        kill -9 "$job_pid" 2>/dev/null || true
        rc=0
        forced=1
        break
      fi
    fi

    if ! kill -0 "$job_pid" 2>/dev/null; then
      wait "$job_pid"
      rc=$?
      break
    fi

    if (( elapsed > TIMEOUT_MIN * 60 )); then
      echo "[worker:${WORKER_ID}] timeout after ${elapsed}s" | tee -a "$TASK_OUTPUT" "$run_output" >/dev/null
      kill "$job_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$job_pid" 2>/dev/null || true
      rc=124
      forced=1
      break
    fi

    sleep 2
  done

  # one retry using claude --continue only for retryable failures
  retried="0"
  retryable="0"
  if [[ "$rc" != "0" ]]; then
    if grep -Eiq "timeout|timed out|ECONN|ENOTFOUND|fetch failed|api error|429|5[0-9]{2}|connection reset|network" "$TASK_OUTPUT"; then
      retryable="1"
    fi

    if [[ "$retryable" == "1" ]]; then
      retried="1"
      echo "[worker:${WORKER_ID}] retryable failure detected rc=$rc, retrying with --continue" | tee -a "$TASK_OUTPUT" "$run_output" >/dev/null

      retry_cmd=(python3 "$RUNNER" --claude-bin "$CLAUDE_BIN" --continue-latest --permission-mode "$PERMISSION_MODE" --workdir "$WORKDIR")
      [[ -n "$ALLOWED_TOOLS" ]] && retry_cmd+=(--allowed-tools "$ALLOWED_TOOLS")
      [[ -n "$TEAMMATE_MODE" ]] && retry_cmd+=(--teammate-mode "$TEAMMATE_MODE")
      [[ -n "$MODEL" ]] && retry_cmd+=(--model "$MODEL")
      [[ "$AGENT_TEAMS" == "1" ]] && retry_cmd+=(--agent-teams)
      "${retry_cmd[@]}" >>"$TASK_OUTPUT" 2>>"$TASK_OUTPUT"
      rc=$?
    else
      echo "[worker:${WORKER_ID}] non-retryable failure rc=$rc, skip --continue retry" | tee -a "$TASK_OUTPUT" "$run_output" >/dev/null
    fi
  fi

  set -e

  echo "$rc" > "$TASK_EXIT"
  echo "$rc" > "$run_exit"

  status="done"
  event="Stop"
  if [[ "$rc" != "0" ]]; then
    status="failed"
    event="Failed"
  fi
  if [[ "$forced" == "1" && "$rc" == "0" ]]; then
    event="ForcedStopAfterDeliverable"
  elif [[ "$retried" == "1" && "$rc" == "0" ]]; then
    event="ContinueRetrySuccess"
  elif [[ "$retryable" == "0" && "$rc" != "0" ]]; then
    event="FailedNonRetryable"
  fi

  jq --arg rc "$rc" --arg ts "$(date -Iseconds)" --arg st "$status" --arg ev "$event" --arg run_id "$run_id" --arg worker "$WORKER_ID" '.status=$st | .finished_at=$ts | .exit_code=($rc|tonumber) | .event=$ev | .run_id=$run_id | .worker_id=$worker' "$running_file" > "${running_file}.tmp" && mv "${running_file}.tmp" "$running_file"

  cb_channel="$(jq -r '.callback.channel // "discord"' "$running_file")"
  cb_target="$(jq -r '.callback.target // ""' "$running_file")"
  cb_account="$(jq -r '.callback.account // ""' "$running_file")"

  cp "$running_file" "$run_meta"
  mv "$running_file" "${DONE_DIR}/${base}"
  jq -n --arg task "$TASK_NAME" --arg status "$status" --arg event "$event" --arg ts "$(date -Iseconds)" --arg run_id "$run_id" --arg worker "$WORKER_ID" --arg cbc "$cb_channel" --arg cbt "$cb_target" --arg cba "$cb_account" '{task_name:$task,status:$status,event:$event,timestamp:$ts,run_id:$run_id,worker_id:$worker,callback:{channel:$cbc,target:$cbt,account:$cba}}' > "$LATEST_FILE"
  started_at="$(jq -r '.started_at // ""' "$run_meta" 2>/dev/null || true)"
  jq -n --arg task "$TASK_NAME" --arg status "$status" --arg ts "$(date -Iseconds)" --arg rc "$rc" --arg run_id "$run_id" --arg worker "$WORKER_ID" --arg started "$started_at" '{task_name:$task,status:$status,started_at:$started,finished_at:$ts,exit_code:($rc|tonumber),run_id:$run_id,worker_id:$worker}' > "$META_FILE"

  echo "[worker:${WORKER_ID}] finished task=$TASK_NAME run_id=$run_id rc=$rc event=$event at $(date -Iseconds)"

  # proactive wake so supervisor can report immediately (hook remains backup)
  if [[ -x "$NOTIFY_BIN" ]]; then
    "$NOTIFY_BIN" "cc_task_done" "task=${TASK_NAME} run_id=${run_id} status=${status} event=${event}" || true
  fi
done
