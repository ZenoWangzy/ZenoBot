#!/usr/bin/env bash
# on-failure.sh - 任务失败 Hook
# 在 Claude Code 任务失败后执行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/run-state.sh"
source "${SCRIPT_DIR}/../lib/clock.sh"
source "${SCRIPT_DIR}/notify.sh"

# 默认错误尾部行数
ERROR_TAIL_LINES=30

on_failure() {
    local run_id="${1:-}"
    local exit_code="${2:-1}"
    local error_summary="${3:-}"

    if [[ -z "$run_id" ]]; then
        echo "ERROR: run_id is required" >&2
        return 1
    fi

    echo "=== Failure Hook ==="
    echo "Run ID: $run_id"
    echo "Exit Code: $exit_code"

    # 检查 run 是否存在
    if ! run_exists "$run_id"; then
        echo "ERROR: Run not found: $run_id" >&2
        return 1
    fi

    local meta_file
    meta_file=$(get_meta_path "$run_id")

    # 幂等检查
    if [[ "$(json_get "$meta_file" ".notify.failure_sent")" == "true" ]]; then
        echo "[SKIP] Failure already processed"
        return 0
    fi

    # 更新状态
    echo "Updating status to failed..."
    update_run_status "$run_id" "failed"

    # 抽取错误尾部（如果没有提供）
    if [[ -z "$error_summary" ]]; then
        error_summary=$(tail_output "$run_id" "$ERROR_TAIL_LINES")
        # 截断到合理长度
        if [[ ${#error_summary} -gt 1000 ]]; then
            error_summary="${error_summary:0:1000}... (truncated)"
        fi
    fi

    # 记录结果
    local ts
    ts=$(now_ts)
    json_update "$meta_file" \
        ".result.exit_code = ${exit_code}" \
        ".result.summary = \"Task failed with exit code ${exit_code}\"" \
        ".result.error_tail = \"${error_summary}\"" \
        ".result.failed_at = ${ts}"

    # 停止 watcher
    echo "Stopping watcher..."
    stop_watcher "$run_id"

    # 发送失败通知
    echo "Sending failure notification..."
    notify_failure "$run_id" "$exit_code" "$error_summary"

    # 归档
    echo "Archiving run..."
    local archive_dir
    archive_dir=$(archive_run "$run_id")
    echo "Archived to: $archive_dir"

    echo "=== Failure Hook Complete ==="
}

# ============================================
# 命令行入口
# ============================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    on_failure "$@"
fi
