#!/usr/bin/env bash
# progress-watch.sh - Progress Watcher 主循环
# 每 5 分钟检查任务状态并发送进度通知

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/run-state.sh"
source "${SCRIPT_DIR}/../lib/clock.sh"
source "${SCRIPT_DIR}/../hooks/notify.sh"

# 默认检查间隔（秒）
DEFAULT_INTERVAL=300

watch_progress() {
    local run_id="${1:-}"

    if [[ -z "$run_id" ]]; then
        echo "ERROR: run_id is required" >&2
        exit 1
    fi

    echo "=== Progress Watcher Started ==="
    echo "Run ID: $run_id"
    echo "PID: $$"
    echo "Started at: $(format_ts)"

    # 获取检查间隔
    local meta_file
    meta_file=$(get_meta_path "$run_id")
    local interval
    interval=$(json_get "$meta_file" ".watcher.interval_sec" 2>/dev/null || echo "$DEFAULT_INTERVAL")
    interval="${interval:-$DEFAULT_INTERVAL}"

    echo "Check interval: $((interval / 60)) minutes"

    # 主循环
    while true; do
        # 检查 run 是否仍在运行
        if ! is_run_active "$run_id"; then
            local status
            status=$(get_run_status "$run_id")
            echo "[EXIT] Run no longer active, status=$status"
            break
        fi

        # 检查输出是否有变化
        local has_changes="false"
        if has_output_changed "$run_id"; then
            has_changes="true"
        fi

        # 获取输出尾部作为摘要
        local summary=""
        if [[ "$has_changes" == "true" ]]; then
            summary=$(tail_output "$run_id" 3 | head -c 200)
            if [[ -n "$summary" ]]; then
                summary="(最近输出: ${summary}...)"
            fi
        fi

        # 发送进度通知（会被节流）
        notify_progress "$run_id" "$has_changes" "$summary"

        # 更新心跳
        update_heartbeat "$run_id"

        # 等待下一次检查
        echo "[SLEEP] Waiting $((interval / 60)) minutes until next check..."
        sleep "$interval"
    done

    echo "=== Progress Watcher Exited ==="
    echo "Run ID: $run_id"
    echo "Exited at: $(format_ts)"
}

# ============================================
# 命令行入口
# ============================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    watch_progress "$@"
fi
