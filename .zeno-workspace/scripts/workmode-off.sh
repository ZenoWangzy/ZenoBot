#!/usr/bin/env bash
set -euo pipefail

SUDO="sudo -n"
PID_FILE="/tmp/openclaw-workmode-caffeinate.pid"

if ! $SUDO /usr/bin/pmset -g >/dev/null 2>&1; then
  echo "[workmode] ERROR: sudo免密未配置或未放行pmset，无法自动切换。"
  echo "[workmode] 请在 /etc/sudoers.d/openclaw-workmode 放行 /usr/bin/pmset 后重试。"
  exit 1
fi

echo "[workmode] Disabling (back to power-save)..."

# 仅恢复关键行为：允许自动睡眠
$SUDO pmset -b sleep 10
$SUDO pmset -c sleep 1

# 只结束本脚本启动的 caffeinate
if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" || true
  fi
  rm -f "$PID_FILE"
fi

echo "[workmode] Disabled"
pmset -g custom | sed -n '/Battery Power/,/AC Power/p' || true