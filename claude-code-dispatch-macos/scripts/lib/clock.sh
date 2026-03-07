#!/usr/bin/env bash
# clock.sh - 时间工具函数

set -euo pipefail

# 获取当前 Unix 时间戳（秒）
now_ts() {
    date +%s
}

# 时间戳格式化为可读格式
format_ts() {
    local ts="${1:-$(now_ts)}"
    date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts"
}

# Alias for format_ts (ISO format)
ts_to_iso() {
    format_ts "$@"
}

# 计算两个时间戳的差值（秒）
ts_diff() {
    local start_ts="$1"
    local end_ts="${2:-$(now_ts)}"
    echo $(( end_ts - start_ts ))
}

# 格式化秒数为人类可读（如 "5m 30s"）
format_duration() {
    local seconds="$1"
    local mins=$((seconds / 60))
    local secs=$((seconds % 60))

    if [[ $mins -gt 0 ]]; then
        echo "${mins}m ${secs}s"
    else
        echo "${secs}s"
    fi
}
