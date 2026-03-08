#!/bin/bash
# Discord 响应检查脚本

set -euo pipefail

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
SESSION_DIR="$HOME/.openclaw/agents/supervisor/sessions"
LOG_FILE="/tmp/discord-response-check.log"
WAKE_URL="http://127.0.0.1:${GATEWAY_PORT}/hooks/wake"

log() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $*" >> "$LOG_FILE"
}

is_gateway_busy() {
    local latest_session
    latest_session=$(find "$SESSION_DIR" -name "*.jsonl" -type f 2>/dev/null | head -1)
    if [[ -z "$latest_session" ]]; then return 1; fi
    local last_modified=$(stat -f %m "$latest_session" 2>/dev/null || echo "0")
    local now=$(date +%s)
    local diff=$((now - last_modified))
    [[ $diff -lt 300 ]] && return 0 || return 1
}

check_last_message_has_reply() {
    local session_file=$(find "$SESSION_DIR" -name "*.jsonl" -type f 2>/dev/null | head -1)
    [[ -z "$session_file" ]] && return 0
    
    local last_user_ts=$(grep -a "\"role\":\"user\"" "$session_file" 2>/dev/null | tail -1 | jq -r ".timestamp // \"1970-01-01T00:00:00Z\"")
    local last_user_text=$(grep -a "\"role\":\"user\"" "$session_file" 2>/dev/null | tail -1 | jq -r "(.content[0].text // \"\")[:50]" 2>/dev/null)
    local last_assistant_ts=$(grep -a "\"role\":\"assistant\"" "$session_file" 2>/dev/null | grep -v "toolCall" | tail -1 | jq -r ".timestamp // \"1970-01-01T00:00:00Z\"" 2>/dev/null)
    
    echo "$last_user_text" | grep -qE "HEARTBEAT|System Message|^\[" && return 0
    
    if [[ "$last_user_ts" > "$last_assistant_ts" ]]; then
        log "Missing reply: user=$last_user_ts > assistant=$last_assistant_ts"
        return 1
    fi
    return 0
}

trigger_wake() {
    log "Triggering wake..."
    curl -sf --noproxy "*" -X POST "$WAKE_URL" -H "Content-Type: application/json" \
        -d "{\"event\":\"discord_response_check\",\"reason\":\"user_message_without_reply\"}" 2>/dev/null && log "Wake sent"
}

main() {
    is_gateway_busy && { log "Gateway busy, skip"; exit 0; }
    check_last_message_has_reply || trigger_wake
}

main "$@"
