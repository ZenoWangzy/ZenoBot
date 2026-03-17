#!/usr/bin/env bash
set -euo pipefail

DISPATCH_BIN="/Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/scripts/dispatch-claude.sh"
TEMPLATE="/Users/ZenoWang/.openclaw/skills/superpowers-aware-dispatch/references/prompt-template.md"

TASK=""
NAME="sp-task-$(date +%s)"
WORKDIR="/Users/ZenoWang/.openclaw/workspace"
MODE="semi-auto"
REPORT_PATH="/Users/ZenoWang/.openclaw/workspace/cc-superpowers-report.md"
AGENT_TEAMS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --workdir) WORKDIR="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --report-path) REPORT_PATH="$2"; shift 2;;
    --agent-teams) AGENT_TEAMS=1; shift;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if [[ -z "$TASK" ]]; then
  echo "--task is required"
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template missing: $TEMPLATE"
  exit 1
fi

PROMPT=$(cat "$TEMPLATE")
PROMPT=${PROMPT//<TASK>/$TASK}
PROMPT=${PROMPT//<REPORT_PATH>/$REPORT_PATH}
PROMPT="Mode: ${MODE}\n\n${PROMPT}"

CMD=(bash "$DISPATCH_BIN" -p "$PROMPT" -n "$NAME" -w "$WORKDIR" --permission-mode bypassPermissions)
if [[ "$AGENT_TEAMS" -eq 1 ]]; then
  CMD+=(--agent-teams)
fi

"${CMD[@]}"
