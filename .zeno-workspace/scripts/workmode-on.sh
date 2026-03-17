#!/usr/bin/env bash
set -euo pipefail

SUDO="sudo -n"
PID_FILE="/tmp/openclaw-workmode-caffeinate.pid"
LOG_FILE="/tmp/openclaw-caffeinate.log"

if ! $SUDO /usr/bin/pmset -g >/dev/null 2>&1; then
  echo "[workmode] ERROR: sudo免密未配置或未放行pmset，无法自动切换。"
  echo "[workmode] 请在 /etc/sudoers.d/openclaw-workmode 放行 /usr/bin/pmset 后重试。"
  exit 1
fi

echo "[workmode] Enabling (lock screen allowed, no idle sleep)..."

# 仅改最关键行为：不自动睡眠（电池+充电）
$SUDO pmset -b sleep 0
$SUDO pmset -c sleep 0

# 启动 keep-awake（不阻止屏幕休眠）
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "[workmode] caffeinate already running (pid=$(cat "$PID_FILE"))"
else
  nohup caffeinate -imsu >"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
fi

sleep 1

echo "[workmode] Enabled"
pmset -g batt | head -n 2 || true
pmset -g custom | sed -n '/Battery Power/,/AC Power/p' || true
echo "[workmode] caffeinate pid: $(cat "$PID_FILE" 2>/dev/null || echo n/a)"