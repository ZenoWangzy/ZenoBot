#!/usr/bin/env bash
# clock.sh - 时间工具函数

set -euo pipefail

# 获取当前 Unix 时间戳（秒）
now_ts() {
    date +%s
}

# 将 ISO 时间戳或 Unix 时间戳转换为 Unix 时间戳
to_unix_ts() {
    local ts="$1"
    # 如果已经是纯数字，直接返回
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        echo "$ts"
        return
    fi
    # 尝试解析 ISO 格式
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$ts" +%s 2>/dev/null || \
    date -j -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null || \
    date -d "$ts" +%s 2>/dev/null || \
    echo "0"
}

# 时间戳格式化为可读格式
format_ts() {
    local ts="${1:-$(now_ts)}"
    # 如果是 ISO 格式，先转换为 Unix 时间戳
    if [[ "$ts" =~ ^[0-9]{4}- ]]; then
        ts=$(to_unix_ts "$ts")
    fi
    date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts"
}

# 计算两个时间戳的差值（秒）
ts_diff() {
    local start_ts="$1"
    local end_ts="${2:-$(now_ts)}"
    # 转换为 Unix 时间戳
    start_ts=$(to_unix_ts "$start_ts")
    end_ts=$(to_unix_ts "$end_ts")
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
