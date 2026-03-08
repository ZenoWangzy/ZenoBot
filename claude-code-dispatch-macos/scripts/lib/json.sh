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

# Create secure temporary file
# Returns path to temp file on stdout
_make_temp() {
    local base="${1:-json}"
    local tmpdir="${TMPDIR:-/tmp}"
    mktemp "${tmpdir}/${base}.XXXXXXXXXX" 2>/dev/null || echo "${tmpdir}/${base}.$$.$RANDOM"
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

    local tmp
    tmp=$(_make_temp "json-set")
    # Use --arg to properly quote string values
    jq --arg val "$value" "${path} = \$val" "$file" > "$tmp" && mv "$tmp" "$file"
}

# 批量更新 JSON 字段 (支持 jq 参数)
# 用法: json_update <file> [--arg name value | --argjson name value | filter]...
# 示例: json_update meta.json --arg status "done" '.status = $status'
json_update() {
    _require_jq
    local file="$1"
    shift

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    local tmp
    tmp=$(_make_temp "json-update")
    # Collect jq args and filter
    local -a jq_args=()
    local filter="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --arg|--argjson|--slurpfile|--rawfile)
                jq_args+=("$1" "$2" "$3")
                shift 3
                ;;
            *)
                # Treat as filter expression
                if [[ "$filter" == "." ]]; then
                    filter="$1"
                else
                    filter="${filter} | $1"
                fi
                shift
                ;;
        esac
    done

    # Run jq with or without args
    if [[ ${#jq_args[@]} -gt 0 ]]; then
        jq "${jq_args[@]}" "$filter" "$file" > "$tmp" && mv "$tmp" "$file"
    else
        jq "$filter" "$file" > "$tmp" && mv "$tmp" "$file"
    fi
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

    local tmp
    tmp=$(_make_temp "json-append")
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
