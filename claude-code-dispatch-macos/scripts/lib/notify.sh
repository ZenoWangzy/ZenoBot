#!/usr/bin/env bash
# notify.sh - Discord notification module for CC auto-recovery
# Provides alerting with cooldown management

set -euo pipefail

# Get script directory
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${_LIB_SCRIPT_DIR}/clock.sh"

# =============================================================================
# Configuration
# =============================================================================

# Discord webhook URL (required for notifications)
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

# Alert cooldown directory
ALERT_COOLDOWN_DIR="${ALERT_COOLDOWN_DIR:-/tmp/cc-alert-cooldown}"

# Default cooldown periods (seconds)
ALERT_COOLDOWN_DEFAULT=${ALERT_COOLDOWN_DEFAULT:-900}    # 15 minutes
AUTH_FAILURE_COOLDOWN=${AUTH_FAILURE_COOLDOWN:-1800}     # 30 minutes
QUOTA_EXHAUSTED_COOLDOWN=${QUOTA_EXHAUSTED_COOLDOWN:-1800} # 30 minutes

# Ensure cooldown directory exists
mkdir -p "$ALERT_COOLDOWN_DIR" 2>/dev/null || true

# =============================================================================
# Alert Reason Enums (Standardized)
# =============================================================================

# Valid alert reasons (must match design document)
declare -A ALERT_COOLDOWNS=(
    ["fatal_pattern"]=900           # 15 min
    ["retry_exhausted"]=900         # 15 min
    ["dangerous_duplicate"]=900     # 15 min
    ["worker_dead"]=900             # 15 min
    ["hard_stall_unrecoverable"]=900 # 15 min
    ["auth_failure"]=1800           # 30 min
    ["quota_exhausted"]=1800        # 30 min
)

# =============================================================================
# Cooldown Management
# =============================================================================

# Get cooldown period for a reason
get_alert_cooldown() {
    local reason="$1"
    local cooldown="${ALERT_COOLDOWNS[$reason]:-}"
    if [[ -z "$cooldown" ]]; then
        cooldown="$ALERT_COOLDOWN_DEFAULT"
    fi
    echo "$cooldown"
}

# Check if alert is in cooldown
# Returns 0 if should skip (in cooldown), 1 if should send
check_alert_cooldown() {
    local task_name="$1"
    local reason="$2"

    local cooldown_file="${ALERT_COOLDOWN_DIR}/${task_name}__${reason}.ts"
    local cooldown_period
    cooldown_period=$(get_alert_cooldown "$reason")

    if [[ -f "$cooldown_file" ]]; then
        local last_sent
        last_sent=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        local now
        now=$(now_ts)
        local elapsed=$((now - last_sent))

        if [[ "$elapsed" -lt "$cooldown_period" ]]; then
            local remaining=$((cooldown_period - elapsed))
            return 0  # In cooldown
        fi
    fi

    return 1  # Not in cooldown, should send
}

# Record that an alert was sent
record_alert_sent() {
    local task_name="$1"
    local reason="$2"

    local cooldown_file="${ALERT_COOLDOWN_DIR}/${task_name}__${reason}.ts"
    local now
    now=$(now_ts)

    # Use atomic write
    local tmp="${cooldown_file}.tmp.$$"
    echo "$now" > "$tmp" && mv "$tmp" "$cooldown_file"
}

# =============================================================================
# Discord Webhook Functions
# =============================================================================

# Send Discord alert with embed
# Usage: send_discord_alert <task_name> <run_id> <reason> [details]
send_discord_alert() {
    local task_name="$1"
    local run_id="${2:-}"
    local reason="$3"
    local details="${4:-}"

    # Check if webhook is configured
    if [[ -z "$DISCORD_WEBHOOK" ]]; then
        echo "[WARN] Discord webhook not configured, skipping alert" >&2
        return 0
    fi

    # Check cooldown
    if check_alert_cooldown "$task_name" "$reason"; then
        echo "[INFO] Alert in cooldown for ${task_name}/${reason}"
        return 0
    fi

    # Validate reason
    if [[ -z "${ALERT_COOLDOWNS[$reason]:-}" ]]; then
        echo "[WARN] Unknown alert reason: $reason, using default cooldown" >&2
    fi

    # Build embed color based on severity
    local color
    case "$reason" in
        fatal_pattern|dangerous_duplicate)
            color=16711680  # Red
            ;;
        auth_failure|quota_exhausted)
            color=16776960  # Yellow
            ;;
        *)
            color=15158332  # Orange
            ;;
    esac

    # Build description
    local description="**Task:** ${task_name}"
    if [[ -n "$run_id" ]]; then
        description+="\n**Run:** ${run_id}"
    fi
    description+="\n**Reason:** ${reason}"
    if [[ -n "$details" ]]; then
        description+="\n**Details:** ${details}"
    fi

    # Build JSON payload
    local payload
    payload=$(cat <<EOF
{
  "embeds": [
    {
      "title": "⚠️ CC CLI Alert",
      "description": "${description}",
      "color": ${color},
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "fields": [
        { "name": "Status", "value": "${reason}", "inline": true }
      ]
    }
  ]
}
EOF
)

    # Send to Discord
    local response
    local http_code
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$DISCORD_WEBHOOK" 2>/dev/null)

    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" == "204" ]]; then
        # Record successful send
        record_alert_sent "$task_name" "$reason"
        echo "[INFO] Discord alert sent: ${task_name}/${reason}"
        return 0
    else
        echo "[ERROR] Discord alert failed: HTTP ${http_code}" >&2
        return 1
    fi
}

# Send a simple Discord message (for testing or non-alert purposes)
send_discord_message() {
    local content="$1"

    if [[ -z "$DISCORD_WEBHOOK" ]]; then
        echo "[WARN] Discord webhook not configured, skipping message" >&2
        return 0
    fi

    local payload
    payload=$(printf '{"content":%s}' "$(echo "$content" | jq -Rs .)")

    local response
    local http_code
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$DISCORD_WEBHOOK" 2>/dev/null)

    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" == "204" ]]; then
        return 0
    else
        echo "[ERROR] Discord message failed: HTTP ${http_code}" >&2
        return 1
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Clear all cooldowns (for testing)
clear_all_cooldowns() {
    rm -rf "${ALERT_COOLDOWN_DIR:?}"/* 2>/dev/null || true
}

# List current cooldowns
list_cooldowns() {
    local now
    now=$(now_ts)

    for file in "$ALERT_COOLDOWN_DIR"/*.ts 2>/dev/null; do
        [[ -f "$file" ]] || continue
        local basename
        basename=$(basename "$file" .ts)
        local last_sent
        last_sent=$(cat "$file" 2>/dev/null || echo "0")
        local elapsed=$((now - last_sent))
        local remaining=$((900 - elapsed))
        if [[ "$remaining" -gt 0 ]]; then
            echo "${basename}: ${remaining}s remaining"
        fi
    done
}
