#!/bin/zsh
set -euo pipefail

WORKDIR="/Users/ZenoWang/.openclaw/workspace/skills/evolver"
LOGFILE="/Users/ZenoWang/.openclaw/workspace/logs/evolver-loop.log"

mkdir -p "$(dirname "$LOGFILE")"

# Prevent duplicate loop processes
if pgrep -f "node index.js --loop" >/dev/null 2>&1; then
  echo "[$(date '+%F %T')] evolver loop already running, skip." >> "$LOGFILE"
  exit 0
fi

cd "$WORKDIR"
nohup node index.js --loop >> "$LOGFILE" 2>&1 &
echo "[$(date '+%F %T')] started evolver loop." >> "$LOGFILE"
