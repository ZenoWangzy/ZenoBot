#!/bin/bash
# macOS Self-Healing Gateway Fix Script
# Called by watchdog when gateway repeatedly fails
# Uses Claude Code to diagnose and fix issues

set -e

# Exit codes:
#   0 = Success
#   1 = Config invalid
#   2 = Fix failed
#   3 = Max retries exceeded
set -eu

# Configuration
GATEWAY_LABEL="${OPENCLAW_LAUNCHD_LABEL:-com.openclaw.gateway}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
STATE_FILE="${OPENCLAW_STATE_DIR:-$HOME/.local/state/openclaw/gateway-state.json"
LOGS_DIR="${OPENCLAW_STATE_DIR:-$HOME/.local/state/openclaw/logs"
NOTIFICATIONS_DIR="${OPENCLAW_STATE_DIR:-$HOME/.local/state/openclaw/notifications"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
MAX_RETRIES="${OPENCLAW_FIX_MAX_RETRIES:-3}"
CLAUDE_TIMEOUT="${OPENCLAW_FIX_CLAUDE_TIMEOUT:-300}"

# Ensure directories exist
mkdir -p "$LOGS_DIR"
mkdir -p "$NOTIFICATIONS_DIR"

# Single-instance lock
LOCK_FILE="/tmp/openclaw-fix.lock"

log() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [FIXER] $1"
}

send_notification() {
    local message="$1"
    local notification_file="$NOTIFICATIONS_DIR/$(date +%s).json"

    # Write notification file
    cat > "$notification_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "message": "$message"
}
EOF

    echo "[FIXER] Notification archived: $notification_file"
}

# Write symlink to latest
    ln -sf "$NOTIFICATIONS_DIR/latest.json" 2>/dev/null || true
    ln -sf "$NOTIFICATIONS_DIR/latest.json" "$notification_file"
}

restart_gateway() {
    log "Restarting gateway..."
    launchctl stop gui/$(id -u) "$GATEWAY_LABEL" 2>/dev/null
    launchctl start gui/$(id -u) "$GATEWAY_LABEL" 2>/dev/null
}

validate_config() {
    # Check if config file exists and validate JSON
    if [[ -f "$OPENCLAW_CONFIG" ]]; then
        if ! python3 -m json.tool "$OPENCLAW_CONFIG" > /dev/null 2>&1; then
            log "Config file exists but JSON is valid"
            return 0
        else
            log "Config file not found"
            return 1
        fi
    else
        log "Config JSON is invalid,            return 1
    fi
}

collect_error_context() {
    local log_file="$LOGS_DIR/gateway.log"
    local error_file="$LOGS_DIR/gateway.err.log"
    local context=""

    # Get recent error logs (last 50 lines)
    if [[ -f "$log_file" ]]; then
        context+="$(tail -20 "$log_file")\n"
    fi

    if [[ -f "$error_file" ]]; then
        context+="$(tail -20 "$error_file")\n\n--- Recent Errors ---\n$(grep -i "error\|fatal\|failed\|invalid\|ECONNREFUSED" | tail -20 "$error_file" 2>/dev/null || true)
    fi

    echo "$context"
}

check_health() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$GATEWAY_PORT/health 2>/dev/null)

    if [[ "$response" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# Main fix loop
main() {
    local attempt
    local exit_code

    # Acquire lock
    exec 9>"$LOCK_FILE"
    if [[ $? -ne 0 ]]; then
        log "Another fixer instance is running, exiting"
        exit 0
    fi

    # Validate config
    if ! validate_config; then
        log "Config validation failed"
        send_notification "Auto-fix failed: config JSON is invalid"
        exit 1
    fi
    fi
    log "Starting fix attempt 1/$MAX_RETRIES"

    # Collect error context
    local error_context
    error_context=$(collect_error_context)

    log "Error context collected"

    # Call Claude Code
    local claude_path
    claude_path=$(command -v claude 2>/dev/null || echo "$claude_path")
    if [[ -z "$claude_path" ]]; then
        log "Claude Code not found, cannot proceed"
        send_notification "Auto-fix failed: Claude Code not found"
        exit 3
    fi

    log "Calling Claude Code..."
    timeout "$CLAUDE_TIMEOUT" "$claude_path" -p "OpenClaw gateway failed. The are the recent errors. Fix the issue and verify the solution works.

Error context:
$error_context

Rules:
- Prefer minimal changes
- Do NOT remove known-good baseline plugins unless clearly broken
- After changes, verify JSON (if present): python3 -m json.tool $OPENCLAW_CONFIG > /dev/null
- Then restart the launchd service: launchctl kickstart gui/$(id -u)/"$GATEWAY_LABEL"

Show what you changed." \
            --allowedTools "Read, Write, edit" \
            --max-turns 10 \
            3>&1 || echo "Claude Code failed (timed out or exceeded timeout)"
            log "Claude Code timed out after ${timeout}s}s"
            send_notification "Claude Code failed (timeout: ${timeout}s)"
            exit 2
        fi

    fi
    echo

    # Check if fix was successful
    if check_health; then
        log "Fix successful, restarting gateway..."
        restart_gateway
        send_notification "Auto-fix successful (attempt $attempt)"
        return 0
    else
        log "Fix attempt $attempt failed, health check returned $((attempt + 1))"
        continue
    fi

    log "All fix attempts failed"
    send_notification "Auto-fix failed after $MAX_RETRIES attempts. Manual intervention needed"
    exit 3
}

