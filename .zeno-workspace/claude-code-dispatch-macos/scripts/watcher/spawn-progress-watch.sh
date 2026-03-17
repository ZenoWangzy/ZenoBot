#!/usr/bin/env bash
# spawn-progress-watch.sh - 启动 Progress Watcher
# 在后台拉起 watcher 进程

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHER_SCRIPT="${SCRIPT_DIR}/progress-watch.sh"

spawn_watcher() {
    local run_id="${1:-}"

    if [[ -z "$run_id" ]]; then
        echo "ERROR: run_id is required" >&2
        return 1
    fi

    # 检查是否已有 watcher 在运行
    local pid_file
    pid_file=$(get_watcher_pid_path "$run_id" 2>/dev/null || echo "")

    if [[ -n "$pid_file" ]] && [[ -f "$pid_file" ]]; then
        local existing_pid
        existing_pid=$(cat "$pid_file" 2>/dev/null || echo "")

        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            echo "[SKIP] Watcher already running for $run_id (PID: $existing_pid)"
            return 0
        fi
    fi

    # 确保脚本可执行
    if [[ ! -x "$WATCHER_SCRIPT" ]]; then
        chmod +x "$WATCHER_SCRIPT"
    fi

    # 在后台启动 watcher
    local log_file="/tmp/cc-progress-watch-${run_id}.log"
    nohup "$WATCHER_SCRIPT" "$run_id" > "$log_file" 2>&1 &
    local pid=$!

    # 等待一小段时间确认进程启动
    sleep 0.5

    if kill -0 "$pid" 2>/dev/null; then
        # 记录 PID
        set_watcher_pid "$run_id" "$pid"
        echo "[OK] Watcher spawned for $run_id (PID: $pid)"
        echo "Log file: $log_file"
    else
        echo "[ERROR] Failed to spawn watcher, check log: $log_file"
        return 1
    fi
}

# ============================================
# 命令行入口
# ============================================

# 引入 run-state（需要在函数之后，因为 spawn_watcher 会用到）
source "${SCRIPT_DIR}/../lib/run-state.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    spawn_watcher "$@"
fi
