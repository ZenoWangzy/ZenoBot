#!/bin/bash
# OpenClaw Gateway 健康检查脚本
#
# 用途: 每30秒由 LaunchAgent 调用，检查 Gateway 健康状态
# 行为: 健康时静默退出，不健康时调用修复脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
FIX_SCRIPT="${SCRIPT_DIR}/openclaw-fix.sh"
HEALTH_URL="http://127.0.0.1:${GATEWAY_PORT}/health"
TIMEOUT=5
LOG_FILE="/tmp/openclaw-health-check.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# 检查 Gateway 是否运行
if ! pgrep -f "openclaw.*gateway" > /dev/null 2>&1; then
    log "Gateway process not found, triggering fix..."
    "$FIX_SCRIPT"
    exit $?
fi

# 检查健康端点
if ! curl -sf --max-time "$TIMEOUT" "$HEALTH_URL" > /dev/null 2>&1; then
    log "Health check failed (port ${GATEWAY_PORT}), triggering fix..."
    "$FIX_SCRIPT"
    exit $?
fi

# 健康状态，静默退出
exit 0
