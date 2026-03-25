#!/bin/bash
# OpenClaw Gateway 健康检查脚本 - 含 Discord 响应检查

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
FIX_SCRIPT="${SCRIPT_DIR}/openclaw-fix.sh"
DISCORD_CHECK_SCRIPT="${SCRIPT_DIR}/discord-response-check.sh"
HEALTH_URL="http://127.0.0.1:${GATEWAY_PORT}/health"
TIMEOUT=5
LOG_FILE="/tmp/openclaw-health-check.log"

log() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $*" >> "$LOG_FILE"
}

# 检查 Gateway 是否运行
if ! pgrep -f "openclaw.*gateway" > /dev/null 2>&1; then
    log "Gateway process not found, triggering fix..."
    "$FIX_SCRIPT"
    exit $?
fi

# 检查健康端点
if ! curl -sf --noproxy "*" --max-time "$TIMEOUT" "$HEALTH_URL" > /dev/null 2>&1; then
    log "Health check failed (port ${GATEWAY_PORT}), triggering fix..."
    "$FIX_SCRIPT"
    exit $?
fi

# 检查 Discord 消息是否有回复
if [[ -x "$DISCORD_CHECK_SCRIPT" ]]; then
    "$DISCORD_CHECK_SCRIPT" 2>/dev/null || true
fi

exit 0
