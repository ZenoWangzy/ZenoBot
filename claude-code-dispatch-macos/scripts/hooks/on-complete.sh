#!/usr/bin/env bash
# on-complete.sh - 任务完成 Hook
# 在 Claude Code 任务成功结束后执行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/run-state.sh"
source "${SCRIPT_DIR}/../lib/clock.sh"
source "${SCRIPT_DIR}/notify.sh"

on_complete() {
    local run_id="${1:-}"
    local summary="${2:-}"

    if [[ -z "$run_id" ]]; then
        echo "ERROR: run_id is required" >&2
        return 1
    fi

    echo "=== Completion Hook ==="
    echo "Run ID: $run_id"

    # 检查 run 是否存在
    if ! run_exists "$run_id"; then
        echo "ERROR: Run not found: $run_id" >&2
        return 1
    fi

    local meta_file
    meta_file=$(get_meta_path "$run_id")

    # 幂等检查
    if [[ "$(json_get "$meta_file" ".notify.completion_sent")" == "true" ]]; then
        echo "[SKIP] Completion already processed"
        return 0
    fi

    # 更新状态
    echo "Updating status to done..."
    update_run_status "$run_id" "done"

    # 记录结果
    local ts
    ts=$(now_ts)
    json_update "$meta_file" \
        ".result.exit_code = 0" \
        ".result.summary = \"${summary:-Task completed successfully}\"" \
        ".result.completed_at = ${ts}"

    # 生成摘要（如果没有提供）
    if [[ -z "$summary" ]]; then
        local task_name
        task_name=$(json_get "$meta_file" ".task_name")
        summary="Task '${task_name}' completed successfully"
    fi

    # 停止 watcher
    echo "Stopping watcher..."
    stop_watcher "$run_id"

    # 发送完成通知
    echo "Sending completion notification..."
    notify_complete "$run_id" "$summary"

    # 归档
    echo "Archiving run..."
    local archive_dir
    archive_dir=$(archive_run "$run_id")
    echo "Archived to: $archive_dir"

    echo "=== Completion Hook Complete ==="
}

# ============================================
# 命令行入口
# ============================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    on_complete "$@"
fi
