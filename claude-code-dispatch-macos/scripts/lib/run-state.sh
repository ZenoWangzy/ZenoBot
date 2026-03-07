#!/usr/bin/env bash
# run-state.sh - 运行状态管理函数

set -euo pipefail

# 引入依赖
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=clock.sh
source "${_LIB_SCRIPT_DIR}/clock.sh"
# shellcheck source=json.sh
source "${_LIB_SCRIPT_DIR}/json.sh"

# 默认数据目录
DATA_DIR="${DATA_DIR:-$(dirname "$(dirname "$(dirname "$_LIB_SCRIPT_DIR")")")/data}"
RUNNING_DIR="${DATA_DIR}/running"
DONE_DIR="${DATA_DIR}/done"

# 确保目录存在
ensure_dirs() {
    mkdir -p "$RUNNING_DIR" "$DONE_DIR"
}

# 生成 run_id
# 用法: generate_run_id <task_name>
generate_run_id() {
    local task_name="$1"
    local ts
    ts=$(now_ts)
    echo "${ts}-${task_name}"
}

# 获取 run 目录路径
get_run_dir() {
    local run_id="$1"
    echo "${RUNNING_DIR}/${run_id}"
}

# 获取 meta.json 路径
get_meta_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/meta.json"
}

# 获取 heartbeat.json 路径
get_heartbeat_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/heartbeat.json"
}

# 获取 task-output.txt 路径
get_output_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/task-output.txt"
}

# 获取 watcher.pid 路径
get_watcher_pid_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/watcher.pid"
}

# 创建新的 run 状态
# 用法: create_run <run_id> <task_name> [extra_json]
create_run() {
    local run_id="$1"
    local task_name="$2"
    local extra_json="${3:-{}}"

    ensure_dirs

    local run_dir
    run_dir=$(get_run_dir "$run_id")
    mkdir -p "$run_dir"

    local ts
    ts=$(now_ts)

    # 创建 meta.json
    local meta_content
    meta_content=$(cat <<EOF
{
  "task_name": "${task_name}",
  "run_id": "${run_id}",
  "status": "running",
  "created_at": ${ts},
  "started_at": ${ts},
  "updated_at": ${ts},
  "notify": {
    "start_sent": false,
    "last_progress_at": 0,
    "completion_sent": false,
    "failure_sent": false
  },
  "watcher": {
    "enabled": true,
    "interval_sec": 300,
    "pid": null
  },
  "result": {
    "exit_code": null,
    "summary": null
  }
}
EOF
)

    # 合并额外字段
    if [[ "$extra_json" != "{}" ]]; then
        meta_content=$(echo "$meta_content" "$extra_json" | jq -s 'add')
    fi

    json_create "$(get_meta_path "$run_id")" "$meta_content"

    # 创建 heartbeat.json
    local heartbeat_content
    heartbeat_content=$(cat <<EOF
{
  "last_output_mtime": ${ts},
  "last_output_size": 0,
  "last_seen_at": ${ts},
  "last_progress_sent_at": 0
}
EOF
)
    json_create "$(get_heartbeat_path "$run_id")" "$heartbeat_content"

    # 创建空的 output 文件
    touch "$(get_output_path "$run_id")"

    echo "$run_dir"
}

# 读取 run 状态
# 用法: get_run_status <run_id>
get_run_status() {
    local run_id="$1"
    json_get "$(get_meta_path "$run_id")" ".status"
}

# 更新 run 状态
# 用法: update_run_status <run_id> <new_status>
update_run_status() {
    local run_id="$1"
    local new_status="$2"
    local ts
    ts=$(now_ts)

    json_update "$(get_meta_path "$run_id")" \
        ".status = \"${new_status}\"" \
        ".updated_at = ${ts}"
}

# 检查 run 是否存在
run_exists() {
    local run_id="$1"
    [[ -f "$(get_meta_path "$run_id")" ]]
}

# 检查 run 是否仍在运行
is_run_active() {
    local run_id="$1"
    local status
    status=$(get_run_status "$run_id")
    [[ "$status" == "running" ]]
}

# 归档 run 到 done 目录
archive_run() {
    local run_id="$1"
    local src_dir
    src_dir=$(get_run_dir "$run_id")
    local dest_dir="${DONE_DIR}/${run_id}"

    if [[ -d "$src_dir" ]]; then
        mv "$src_dir" "$dest_dir"
        echo "$dest_dir"
    else
        echo "ERROR: Run directory not found: $src_dir" >&2
        return 1
    fi
}

# 获取 watcher PID
get_watcher_pid() {
    local run_id="$1"
    local pid_file
    pid_file=$(get_watcher_pid_path "$run_id")

    if [[ -f "$pid_file" ]]; then
        cat "$pid_file"
    else
        echo ""
    fi
}

# 设置 watcher PID
set_watcher_pid() {
    local run_id="$1"
    local pid="$2"
    local pid_file
    pid_file=$(get_watcher_pid_path "$run_id")

    echo "$pid" > "$pid_file"

    # 同时更新 meta.json
    json_update "$(get_meta_path "$run_id")" ".watcher.pid = ${pid}"
}

# 停止 watcher
stop_watcher() {
    local run_id="$1"
    local pid
    pid=$(get_watcher_pid "$run_id")

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        # 等待进程结束
        local i=0
        while kill -0 "$pid" 2>/dev/null && [[ $i -lt 10 ]]; do
            sleep 0.5
            ((i++))
        done
        # 强制杀死
        kill -9 "$pid" 2>/dev/null || true
    fi

    # 清理 pid 文件
    rm -f "$(get_watcher_pid_path "$run_id")"
    json_update "$(get_meta_path "$run_id")" ".watcher.pid = null" 2>/dev/null || true
}

# 更新心跳
update_heartbeat() {
    local run_id="$1"
    local ts
    ts=$(now_ts)
    local output_file
    output_file=$(get_output_path "$run_id")

    local mtime="$ts"
    local size=0

    if [[ -f "$output_file" ]]; then
        mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null || echo "$ts")
        size=$(wc -c < "$output_file" 2>/dev/null || echo 0)
        size=$((size))  # trim whitespace
    fi

    json_update "$(get_heartbeat_path "$run_id")" \
        ".last_output_mtime = ${mtime}" \
        ".last_output_size = ${size}" \
        ".last_seen_at = ${ts}"
}

# 检查是否有输出变化
has_output_changed() {
    local run_id="$1"
    local heartbeat_file
    heartbeat_file=$(get_heartbeat_path "$run_id")
    local output_file
    output_file=$(get_output_path "$run_id")

    if [[ ! -f "$heartbeat_file" ]] || [[ ! -f "$output_file" ]]; then
        return 1
    fi

    local last_mtime last_size current_mtime current_size

    last_mtime=$(json_get "$heartbeat_file" ".last_output_mtime")
    last_size=$(json_get "$heartbeat_file" ".last_output_size")

    current_mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null || echo 0)
    current_size=$(wc -c < "$output_file" 2>/dev/null || echo 0)
    current_size=$((current_size))

    [[ "$current_mtime" != "$last_mtime" ]] || [[ "$current_size" != "$last_size" ]]
}

# 获取输出尾部
tail_output() {
    local run_id="$1"
    local lines="${2:-30}"
    local output_file
    output_file=$(get_output_path "$run_id")

    if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
        tail -n "$lines" "$output_file"
    fi
}
