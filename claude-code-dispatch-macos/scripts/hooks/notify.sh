#!/usr/bin/env bash
# notify.sh - 通知发送模块
# 支持 Discord 作为主要通知渠道

set -euo pipefail

# 引入依赖
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/run-state.sh
source "${SCRIPT_DIR}/../lib/run-state.sh"
# shellcheck source=../lib/clock.sh
source "${SCRIPT_DIR}/../lib/clock.sh"

# Discord webhook URL（从环境变量读取）
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

# 默认通知渠道
NOTIFY_CHANNEL="${NOTIFY_CHANNEL:-discord}"

# 通知节流配置
PROGRESS_INTERVAL_SEC="${PROGRESS_INTERVAL_SEC:-300}"
ALERT_COOLDOWN_SEC="${ALERT_COOLDOWN_SEC:-900}"

# ============================================
# 内部函数
# ============================================

# 发送 Discord 消息
_send_discord() {
    local content="$1"

    if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
        echo "[DISCORD] No webhook configured, skipping: $content"
        return 0
    fi

    # 使用 JSON 格式发送
    local payload
    payload=$(jq -n --arg content "$content" '{content: $content}')

    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$DISCORD_WEBHOOK_URL" >/dev/null

    return $?
}

# 发送到默认渠道
_send() {
    local content="$1"

    case "$NOTIFY_CHANNEL" in
        discord)
            _send_discord "$content"
            ;;
        stdout|*)
            echo "$content"
            ;;
    esac
}

# 标记通知已发送
_mark_sent() {
    local run_id="$1"
    local field="$2"
    local ts
    ts=$(now_ts)

    json_update "$(get_meta_path "$run_id")" ".notify.${field} = true"

    # 如果是进度通知，还要更新时间戳
    if [[ "$field" == "last_progress_at" ]]; then
        json_update "$(get_meta_path "$run_id")" ".notify.last_progress_at = ${ts}"
    fi
}

# 检查是否已发送
_has_sent() {
    local run_id="$1"
    local field="$2"
    local meta_file
    meta_file=$(get_meta_path "$run_id")

    [[ "$(json_get "$meta_file" ".notify.${field}")" == "true" ]]
}

# 检查是否可以发送进度通知（节流）
_can_send_progress() {
    local run_id="$1"
    local meta_file
    meta_file=$(get_meta_path "$run_id")

    local last_progress_at
    last_progress_at=$(json_get "$meta_file" ".notify.last_progress_at")

    # 从未发送过，可以发送
    [[ -z "$last_progress_at" ]] || [[ "$last_progress_at" == "0" ]] && return 0

    # 检查间隔
    local ts
    ts=$(now_ts)
    local elapsed=$((ts - last_progress_at))

    [[ $elapsed -ge $PROGRESS_INTERVAL_SEC ]]
}

# ============================================
# 公开 API
# ============================================

# 发送任务开始通知（幂等）
# 用法: notify_start <run_id> [extra_info]
notify_start() {
    local run_id="$1"
    local extra_info="${2:-}"
    local meta_file
    meta_file=$(get_meta_path "$run_id")

    # 幂等检查
    if _has_sent "$run_id" "start_sent"; then
        echo "[SKIP] Start notification already sent for $run_id"
        return 0
    fi

    local task_name
    task_name=$(json_get "$meta_file" ".task_name")
    local created_at
    created_at=$(json_get "$meta_file" ".created_at")
    local interval
    interval=$(json_get "$meta_file" ".watcher.interval_sec")

    local message
    message=$(cat <<EOF
🚀 **步骤 1/4：已开始**
- **任务**: ${task_name}
- **run_id**: \`${run_id}\`
- **开始时间**: $(format_ts "$created_at")
- **进度检查间隔**: $((interval / 60)) 分钟
${extra_info:+- **备注**: ${extra_info}}
EOF
)

    _send "$message"
    _mark_sent "$run_id" "start_sent"

    echo "[OK] Start notification sent for $run_id"
}

# 发送进度更新通知（节流）
# 用法: notify_progress <run_id> [has_changes] [summary]
notify_progress() {
    local run_id="$1"
    local has_changes="${2:-false}"
    local summary="${3:-}"
    local meta_file
    meta_file=$(get_meta_path "$run_id")

    # 检查是否在运行状态
    local status
    status=$(json_get "$meta_file" ".status")
    if [[ "$status" != "running" ]]; then
        echo "[SKIP] Progress notification skipped, status=$status"
        return 0
    fi

    # 节流检查
    if ! _can_send_progress "$run_id"; then
        local last_at
        last_at=$(json_get "$meta_file" ".notify.last_progress_at")
        echo "[SKIP] Progress throttled, last sent at $(format_ts "$last_at")"
        return 0
    fi

    local task_name
    task_name=$(json_get "$meta_file" ".task_name")
    local created_at
    created_at=$(json_get "$meta_file" ".created_at")
    local elapsed
    elapsed=$(ts_diff "$created_at")

    local change_status
    if [[ "$has_changes" == "true" ]]; then
        change_status="有新输出"
    else
        change_status="无新输出（仍在执行）"
    fi

    local message
    message=$(cat <<EOF
⏳ **进度更新**
- **任务**: ${task_name}
- **run_id**: \`${run_id}\`
- **运行时长**: $(format_duration "$elapsed")
- **状态**: ${change_status}
${summary:+- **摘要**: ${summary}}
EOF
)

    _send "$message"
    _mark_sent "$run_id" "last_progress_at"

    # 同时更新 heartbeat
    json_update "$(get_heartbeat_path "$run_id")" ".last_progress_sent_at = $(now_ts)"

    echo "[OK] Progress notification sent for $run_id"
}

# 发送完成通知（幂等）
# 用法: notify_complete <run_id> [summary]
notify_complete() {
    local run_id="$1"
    local summary="${2:-}"
    local meta_file
    meta_file=$(get_meta_path "$run_id")

    # 幂等检查
    if _has_sent "$run_id" "completion_sent"; then
        echo "[SKIP] Completion notification already sent for $run_id"
        return 0
    fi

    local task_name
    task_name=$(json_get "$meta_file" ".task_name")
    local created_at
    created_at=$(json_get "$meta_file" ".created_at")
    local elapsed
    elapsed=$(ts_diff "$created_at")

    local message
    message=$(cat <<EOF
✅ **步骤 4/4：已完成**
- **任务**: ${task_name}
- **run_id**: \`${run_id}\`
- **运行时长**: $(format_duration "$elapsed")
- **结果**: 成功
${summary:+- **摘要**: ${summary}}
EOF
)

    _send "$message"
    _mark_sent "$run_id" "completion_sent"

    echo "[OK] Completion notification sent for $run_id"
}

# 发送失败通知（幂等）
# 用法: notify_failure <run_id> <exit_code> [error_summary]
notify_failure() {
    local run_id="$1"
    local exit_code="${2:-1}"
    local error_summary="${3:-}"
    local meta_file
    meta_file=$(get_meta_path "$run_id")

    # 幂等检查
    if _has_sent "$run_id" "failure_sent"; then
        echo "[SKIP] Failure notification already sent for $run_id"
        return 0
    fi

    local task_name
    task_name=$(json_get "$meta_file" ".task_name")
    local created_at
    created_at=$(json_get "$meta_file" ".created_at")
    local elapsed
    elapsed=$(ts_diff "$created_at")

    local message
    message=$(cat <<EOF
❌ **任务失败**
- **任务**: ${task_name}
- **run_id**: \`${run_id}\`
- **运行时长**: $(format_duration "$elapsed")
- **Exit Code**: ${exit_code}
${error_summary:+- **错误摘要**:
\`\`\`
${error_summary}
\`\`\`}
- **建议**: 人工检查或重试
EOF
)

    _send "$message"
    _mark_sent "$run_id" "failure_sent"

    echo "[OK] Failure notification sent for $run_id"
}

# ============================================
# 命令行入口
# ============================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-help}"
    shift || true

    case "$cmd" in
        start)
            notify_start "$@"
            ;;
        progress)
            notify_progress "$@"
            ;;
        complete)
            notify_complete "$@"
            ;;
        failure)
            notify_failure "$@"
            ;;
        help|*)
            cat <<EOF
Usage: notify.sh <command> [args]

Commands:
  start <run_id> [extra]       - 发送开始通知
  progress <run_id> [changes] [summary] - 发送进度通知
  complete <run_id> [summary]  - 发送完成通知
  failure <run_id> [exit_code] [error]  - 发送失败通知

Environment:
  DISCORD_WEBHOOK_URL - Discord webhook URL
  NOTIFY_CHANNEL       - 通知渠道 (discord/stdout)
  PROGRESS_INTERVAL_SEC - 进度通知间隔（秒）
EOF
            ;;
    esac
fi
