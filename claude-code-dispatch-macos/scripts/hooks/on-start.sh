#!/usr/bin/env bash
# on-start.sh - 任务开始 Hook
# 在 Claude Code 任务启动后立即执行

set -euo pipefail

# 引入依赖
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/run-state.sh
source "${SCRIPT_DIR}/../lib/run-state.sh"
# shellcheck source=notify.sh
source "${SCRIPT_DIR}/notify.sh"

# ============================================
# 主函数
# ============================================

on_start() {
    local task_name="${1:-}"
    local run_id="${2:-}"
    local extra_info="${3:-}"

    if [[ -z "$task_name" ]]; then
        echo "ERROR: task_name is required" >&2
        return 1
    fi

    # 如果没有提供 run_id，生成一个
    if [[ -z "$run_id" ]]; then
        run_id=$(generate_run_id "$task_name")
    fi

    echo "=== Start Hook ==="
    echo "Task: $task_name"
    echo "Run ID: $run_id"

    # 检查是否已存在
    if run_exists "$run_id"; then
        echo "WARN: Run already exists, checking if start notification sent..."
        local meta_file
        meta_file=$(get_meta_path "$run_id")
        if [[ "$(json_get "$meta_file" ".notify.start_sent")" == "true" ]]; then
            echo "[SKIP] Start notification already sent, exiting"
            return 0
        fi
        echo "Start not sent yet, continuing..."
    else
        # 创建 run 状态
        echo "Creating run state..."
        local run_dir
        run_dir=$(create_run "$run_id" "$task_name")
        echo "Run directory: $run_dir"
    fi

    # 发送开始通知
    echo "Sending start notification..."
    notify_start "$run_id" "$extra_info"

    # 拉起 progress watcher
    echo "Spawning progress watcher..."
    local watcher_script="${SCRIPT_DIR}/../watcher/spawn-progress-watch.sh"
    if [[ -x "$watcher_script" ]]; then
        "$watcher_script" "$run_id"
    else
        echo "WARN: Watcher script not found or not executable: $watcher_script"
    fi

    echo "=== Start Hook Complete ==="
    echo "$run_id"
}

# ============================================
# 命令行入口
# ============================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    on_start "$@"
fi
