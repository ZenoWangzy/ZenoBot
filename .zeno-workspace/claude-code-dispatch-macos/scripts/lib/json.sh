#!/usr/bin/env bash
# json.sh - JSON 读写工具函数
# 依赖: jq

set -euo pipefail

# 检查 jq 是否可用
_require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required but not installed" >&2
        exit 1
    fi
}

# 从 JSON 文件读取字段
# 用法: json_get <file> <path>
# 示例: json_get meta.json ".status"
json_get() {
    _require_jq
    local file="$1"
    local path="${2:-.}"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    jq -r "${path} // empty" "$file" 2>/dev/null || echo ""
}

# 写入 JSON 字段
# 用法: json_set <file> <path> <value>
# 示例: json_set meta.json ".status" "done"
json_set() {
    _require_jq
    local file="$1"
    local path="$2"
    local value="$3"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    local tmp="${file}.tmp.$$"
    jq "${path} = ${value}" "$file" > "$tmp" && mv "$tmp" "$file"
}

# 批量更新 JSON 字段
# 用法: json_update <file> <updates...>
# 示例: json_update meta.json '.status="done"' '.updated_at=1234567890'
json_update() {
    _require_jq
    local file="$1"
    shift

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    local tmp="${file}.tmp.$$"
    # 用管道符连接多个更新操作
    local filter
    filter=$(IFS='|'; echo "$*")
    jq "$filter" "$file" > "$tmp" && mv "$tmp" "$file"
}

# 创建新的 JSON 文件
# 用法: json_create <file> <json-content>
json_create() {
    _require_jq
    local file="$1"
    local content="$2"

    # 确保目录存在
    mkdir -p "$(dirname "$file")"

    echo "$content" | jq '.' > "$file"
}

# 追加数组元素
# 用法: json_array_append <file> <path> <value>
json_array_append() {
    _require_jq
    local file="$1"
    local path="$2"
    local value="$3"

    local tmp="${file}.tmp.$$"
    jq "${path} += [${value}]" "$file" > "$tmp" && mv "$tmp" "$file"
}

# 检查 JSON 字段是否存在且非空
# 用法: json_has <file> <path>
json_has() {
    _require_jq
    local file="$1"
    local path="$2"

    [[ -f "$file" ]] && jq -e "${path} != null and ${path} != \"\"" "$file" &>/dev/null
}
