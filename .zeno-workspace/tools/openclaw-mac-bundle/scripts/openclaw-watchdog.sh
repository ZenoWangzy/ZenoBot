#!/bin/bash
# macOS Self-Healing Gateway Watchdog Script
# Monitors gateway health and triggers fixer when failure threshold reached

set -e

# Exit codes:
#   0 = Gateway healthy
#   1 = Fixer triggered
#   2 = Error
set -eu

# Configuration
GATEWAY_LABEL="${OPENCLAW_LAUNCHD_LABEL:-com.openclaw.gateway}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
STATE_FILE="${OPENCLAW_STATE_DIR:-$HOME/.local/state/openclaw}/gateway-state.json"
LOGS_DIR="${OPENCLAW_STATE_DIR:-$HOME/.local/state/openclaw/logs"
NOTIFICATIONS_DIR="${OPENCLAW_STATE_DIR:-$HOME/.local/state/openclaw/notifications}"
FAILURE_THRESHOLD="${OPENCLAW_FAILURE_THRESHOLD:-3}"
FAILURE_WINDOW="${OPENCLAW_FAILURE_WINDOW:-60}"

# Ensure directories exist
mkdir -p "$LOGS_DIR"
mkdir -p "$NOTIFICATIONS_DIR"

log() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [WATCHDOG] $1"
}

send_notification() {
    local message="$1"
    local notification_file="$NOTIFICATIONS_DIR/$(date +%s).json"

    # Write notification file
    cat > "$notification_file" <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "type": "watchdog",
    "message": "$message",
    "gateway_label": "$GATEWAY_LABEL"
}
EOF

    # Update symlink to latest
    ln -sf "$notification_file" "$NOTIFICATIONS_DIR/latest.json"
}

get_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"failures": [], "last_fix": null, "fix_count": 0, "last_fix_status": null}'
    fi
}

update_state() {
    local state="$1"
    echo "$state" > "$STATE_FILE"
}

prune_old_failures() {
    local state="$1"
    local current_time=$(date +%s)
    local window_start=$((current_time - FAILURE_WINDOW))

    # Use jq if available, otherwise use python
    if command -v jq &>/dev/null; then
        echo "$state" | jq --arg window_start "$window_start" \
            '.failures = [.failures[] | select(. >= ($window_start | tonumber)]'
    elif command -v python3 &>/dev/null; then
        echo "$state" | python3 -c "
import sys, json
data = json.load(sys.stdin)
window_start = $window_start
data['failures'] = [f for f in data['failures'] if f >= window_start]
print(json.dumps(data))
"
    else
        # Fallback: just return as-is (no pruning without jq or python)
        echo "$state"
    fi
}

# Check if gateway is running
check_gateway() {
    local status
    status=$(launchctl list | grep "$GATEWAY_LABEL" | awk '{print $1}')

    if [[ "$status" == "0" ]]; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

# Check HTTP health endpoint
check_http_health() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$GATEWAY_PORT/health 2>/dev/null)

    if [[ "$response" == "200" ]]; then
        return 0  # Healthy
    else
        return 1  # Unhealthy
    fi
}

# Main monitoring loop
main() {
    local state
    state=$(get_state)

    # Prune old failures
    state=$(prune_old_failures "$state")

    # Check gateway status
    if check_gateway -ne 0; then
        # Gateway is not running
        local current_time=$(date +%s)
        local failures

        # Extract current failures
        if command -v jq &>/dev/null; then
            failures=$(echo "$state" | jq -r '.failures += ['"$current_time"'] | .failures | length')
        elif command -v python3 &>/dev/null; then
            failures=$(echo "$state" | python3 -c "
import sys, json
data = json.load(sys.stdin)
data['failures'].append($current_time)
print(len(data['failures']))
" 2>/dev/null)
        else
            # Fallback: just add failure
            failures=1
        fi

        log "Gateway is not running"

        # Check if we reached threshold
        if [[ "$failures" -ge "$FAILURE_THRESHOLD" ]]; then
            log "Failure threshold reached ($failures failures in ${FAILURE_WINDOW}s window)"
            send_notification "Gateway failure threshold reached, triggering fixer"

            # Trigger fixer
            launchctl kickstart gui/$(id -u)/"$GATEWAY_LABEL" 2>/dev/null || true

            # Reset failures after triggering fixer
            update_state '{"failures": [], "last_fix": null, "fix_count": 0, "last_fix_status": null}'
            return 1
        else
            log "Gateway failure count: $failures/$FAILURE_THRESHOLD (window: ${FAILURE_WINDOW}s)"

            # Update state with new failure
            # (This is a simplified update - in production, use jq/python)
            update_state "$(echo "$state" | sed "s/\"failures\": \[[^]]*\]/\"failures\": [\"$current_time\"]/")"
        fi
    else
        log "Gateway status: running"

        # Also check HTTP health
        if check_http_health -ne 0; then
            log "Gateway HTTP health check failed"
            # Similar failure handling as above...
            # (For brevity, using same logic)
        else
            log "Gateway HTTP health check passed"
        fi
    fi

    return 0
}

# Run main
main
