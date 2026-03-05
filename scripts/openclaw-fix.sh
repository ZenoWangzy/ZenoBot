#!/bin/bash
# OpenClaw Gateway 自动修复脚本
#
# 用途: 当 Gateway 异常退出时，收集错误日志并调用 Claude Code 进行修复
# 行为: flock 防并发 -> 收集日志 -> Claude 修复 -> 重启 -> 通知

set -euo pipefail

# ============ 配置 ============
LOCK_FILE="/tmp/openclaw-fix.lock"
MAX_RETRIES="${OPENCLAW_FIX_MAX_RETRIES:-2}"
CLAUDE_TIMEOUT="${OPENCLAW_CLAUDE_TIMEOUT:-300}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_LABEL="ai.openclaw.gateway"
LOG_FILE="/tmp/openclaw-fix.log"
GATEWAY_ERR_LOG="$HOME/.openclaw/logs/gateway.err.log"
GATEWAY_LOG="$HOME/.openclaw/logs/gateway.log"

# ============ flock 锁 (防止并发执行) ============
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another fix is running, skipping..." >> "$LOG_FILE"
    exit 0
fi

# ============ 日志函数 ============
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# ============ 收集错误信息 ============
collect_errors() {
    local errors=""

    # 收集 Gateway 错误日志 (最后100行)
    if [[ -f "$GATEWAY_ERR_LOG" ]]; then
        errors+="=== Gateway Error Log ===\n"
        errors+="$(tail -100 "$GATEWAY_ERR_LOG" 2>/dev/null || echo "无法读取")\n\n"
    fi

    # 收集 Gateway 标准日志 (最后50行)
    if [[ -f "$GATEWAY_LOG" ]]; then
        errors+="=== Gateway Log (last 50 lines) ===\n"
        errors+="$(tail -50 "$GATEWAY_LOG" 2>/dev/null || echo "无法读取")\n\n"
    fi

    # 检查 LaunchAgent 状态
    errors+="=== LaunchAgent Status ===\n"
    errors+="$(launchctl list | grep -E "openclaw|PID" || echo "未找到相关服务")\n\n"

    # 检查端口占用
    errors+="=== Port ${GATEWAY_PORT} Status ===\n"
    errors+="$(lsof -i :${GATEWAY_PORT} 2>/dev/null || echo "端口未监听")\n\n"

    # 检查进程
    errors+="=== OpenClaw Processes ===\n"
    errors+="$(ps aux | grep -E "openclaw|OpenClaw" | grep -v grep || echo "无相关进程")\n\n"

    # 检查磁盘空间
    errors+="=== Disk Space (home) ===\n"
    errors+="$(df -h "$HOME" | tail -1)\n"

    echo -e "$errors"
}

# ============ 重启 Gateway ============
restart_gateway() {
    log "Restarting Gateway..."

    # 先尝试优雅停止
    launchctl bootout gui/$UID/$GATEWAY_LABEL 2>/dev/null || true
    sleep 2

    # 强制杀死残留进程
    pkill -9 -f "openclaw.*gateway" 2>/dev/null || true
    sleep 1

    # 启动 Gateway
    launchctl kickstart -k gui/$UID/$GATEWAY_LABEL 2>/dev/null || true
    sleep 3
}

# ============ 健康检查 ============
check_health() {
    curl -sf --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/health" > /dev/null 2>&1
}

# ============ 通知结果 ============
notify_result() {
    local status="$1"
    local retry_count="$2"
    local error_summary="$3"
    local fix_action="$4"

    # 等待 Gateway 恢复
    sleep 2

    # 截断并转义摘要
    local safe_summary
    safe_summary=$(echo "$error_summary" | head -c 300 | tr '"' "'" | tr '\n' ' ')

    local safe_action
    safe_action=$(echo "$fix_action" | head -c 500 | tr '"' "'" | tr '\n' ' ')

    local payload
    payload=$(cat <<EOF
{
  "event": "gateway_auto_fix",
  "status": "${status}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "retry_count": ${retry_count},
  "error_summary": "${safe_summary}",
  "fix_action": "${safe_action}"
}
EOF
)

    log "Sending notification (status: ${status})..."

    if curl -sf -X POST "http://127.0.0.1:${GATEWAY_PORT}/hooks/wake" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null; then
        log "Notification sent successfully"
    else
        log "Warning: Failed to send notification (Gateway may still be recovering)"
    fi
}

# ============ 主流程 ============
main() {
    log "=========================================="
    log "=== Starting auto-fix process ==="
    log "=========================================="

    local errors
    errors=$(collect_errors)

    # 构建修复提示词
    local fix_prompt="OpenClaw Gateway 异常退出，请诊断并修复问题。

## 错误信息
$errors

## 修复指南
请按以下步骤操作:

1. **分析错误日志**
   - 识别关键错误信息
   - 定位根本原因

2. **常见问题处理**
   - 配置文件语法错误: 修复 ~/.openclaw/openclaw.json
   - 端口被占用: 识别并处理冲突进程
   - 依赖缺失: 说明需要安装的包
   - 权限问题: 修复文件权限

3. **修复原则**
   - 只修复明确的问题
   - 不做不必要的改动
   - 保持配置兼容性

请开始诊断和修复。"

    local fix_result=""
    local retry=0

    while [[ $retry -lt $MAX_RETRIES ]]; do
        log "Attempt $((retry + 1))/$MAX_RETRIES: Running Claude Code..."

        # 调用 Claude Code CLI
        if fix_result=$(timeout "$CLAUDE_TIMEOUT" claude -p "$fix_prompt" --allowedTools Read,Write,Edit 2>&1); then
            log "Claude Code completed"
            log "Result preview: $(echo "$fix_result" | head -c 200)..."
        else
            local exit_code=$?
            log "Claude Code exit code: $exit_code"
            fix_result="Claude Code 执行完成 (exit: $exit_code)"
        fi

        # 重启 Gateway
        restart_gateway

        # 检查健康状态
        if check_health; then
            log "✅ Gateway is healthy!"
            notify_result "success" $((retry + 1)) "$errors" "$fix_result"
            log "=== Auto-fix completed successfully ==="
            exit 0
        fi

        retry=$((retry + 1))
        log "Gateway still unhealthy after attempt $retry, retrying..."
        sleep 2
    done

    # 所有重试失败
    log "❌ All retries exhausted, fix failed"
    notify_result "failed" $MAX_RETRIES "$errors" "自动修复失败，需要人工介入。请检查日志: $LOG_FILE"
    log "=== Auto-fix failed ==="
    exit 1
}

main "$@"
