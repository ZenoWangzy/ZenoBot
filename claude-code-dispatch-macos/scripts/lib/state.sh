#!/usr/bin/env bash
# state.sh - State detection module for CC auto-recovery
# Implements soft/hard stall detection, activity signal checking, status transitions

set -euo pipefail

# Get script directory
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_SCRIPT_DIR}/clock.sh"
source "${_LIB_SCRIPT_DIR}/json.sh"
source "${_LIB_SCRIPT_DIR}/utils.sh"

# Configuration
SOFT_STALL_THRESHOLD=${SOFT_STALL_THRESHOLD:-600}   # 10 minutes
HARD_STALL_THRESHOLD=${HARD_STALL_THRESHOLD:-1200}  # 20 minutes
QUEUE_TIMEOUT=${QUEUE_TIMEOUT:-300}                  # 5 minutes

# =============================================================================
# Status Helpers
# =============================================================================

# Get current status from meta.json
get_status() {
    local meta_file="$1"
    json_get "$meta_file" '.status // "unknown"'
}

# Check if task is in active state
is_active_status() {
    local status="$1"
    [[ "$status" =~ ^(queued|claimed|running|recoverable_error|recovering|soft_stalled|hard_stalled)$ ]]
}

# Get started_at timestamp
get_started_at() {
    local meta_file="$1"
    json_get "$meta_file" '.started_at // 0'
}

# Get created_at timestamp
get_created_at() {
    local meta_file="$1"
    json_get "$meta_file" '.created_at // 0'
}

# Get updated_at timestamp
get_updated_at() {
    local meta_file="$1"
    json_get "$meta_file" '.updated_at // 0'
}

# =============================================================================
# Activity Signal Detection
# =============================================================================

# Check for execution activity signals (run-scoped)
# Returns: 0 = has activity, 1 = no activity
has_activity_signal() {
    local run_dir="$1"
    local meta_file="${run_dir}/meta.json"
    local now
    now=$(now_ts)

    # Signal 1: Check recent meta.json update (within 5 min)
    local updated_at=$(get_updated_at "$meta_file")
    if [[ -n "$updated_at" && $((now - updated_at)) -lt 300 ]]; then
        return 0
    fi

    # Signal 2: Check output file changes (task-output.txt)
    local output_file="${run_dir}/task-output.txt"
    if [[ -f "$output_file" ]]; then
        local mtime
        mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null)
        if [[ $((now - mtime)) -lt 300 ]]; then
            return 0
        fi
    fi

    # Signal 3: Check exit code file exists
    if [[ -f "${run_dir}/task-exit-code.txt" ]]; then
        return 0
    fi

    # Signal 4: Check process exists (if pid tracked)
    local pid=$(json_get "$meta_file" '.pid // empty')
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    return 1  # No activity signal
}

# Check for output changes
has_output_changed() {
    local run_dir="$1"
    local heartbeat_file="${run_dir}/heartbeat.json"
    local output_file="${run_dir}/task-output.txt"

    if [[ ! -f "$heartbeat_file" ]] || [[ ! -f "$output_file" ]]; then
        return 1
    fi

    local last_mtime last_size current_mtime current_size

    last_mtime=$(json_get "$heartbeat_file" ".last_output_mtime")
    last_size=$(json_get "$heartbeat_file" ".last_output_size")

    current_mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null || echo 0)
    current_size=$(wc -c < "$output_file" 2>/dev/null || echo 0)
    current_size=$((current_size))  # trim whitespace

    [[ "$current_mtime" != "$last_mtime" ]] || [[ "$current_size" != "$last_size" ]]
}

# =============================================================================
# Stall Detection
# =============================================================================

# Detect soft stall (10 min, no output change)
# Returns: 0 = soft stalled, 1 = not stalled
is_soft_stalled() {
    local run_dir="$1"
    local meta_file="${run_dir}/meta.json"
    local now
    now=$(now_ts)

    local status=$(get_status "$meta_file")
    [[ "$status" != "running" ]] && return 1

    local started_at=$(get_started_at "$meta_file")
    local elapsed=$((now - started_at))

    # Check time threshold
    [[ "$elapsed" -lt "$SOFT_STALL_THRESHOLD" ]] && return 1

    # Check no output change
    if ! has_output_changed "$run_dir"; then
        return 1  # Recent output = not stalled
    fi

    return 0
}

# Detect hard stall (20 min, no activity signals)
# Returns: 0 = hard stalled, 1 = not stalled
is_hard_stalled() {
    local run_dir="$1"
    local meta_file="${run_dir}/meta.json"
    local now
    now=$(now_ts)

    local status=$(get_status "$meta_file")
    [[ "$status" != "running" ]] && return 1

    local started_at=$(get_started_at "$meta_file")
    local elapsed=$((now - started_at))

    # Check time threshold
    [[ "$elapsed" -lt "$HARD_STALL_THRESHOLD" ]] && return 1

    # Check activity signals
    has_activity_signal "$run_dir" && return 1

    return 0
}

# Detect worker dead (queue > 5min unclaimed)
is_worker_dead() {
    local queue_file="$1"
    local now
    now=$(now_ts)

    local created_at=$(get_created_at "$queue_file")
    local status=$(get_status "$queue_file")

    [[ "$status" == "queued" ]] || return 1

    local elapsed=$((now - created_at))
    [[ "$elapsed" -ge "$QUEUE_TIMEOUT" ]]
}

# =============================================================================
# Stall Recording
# =============================================================================

# Record soft stall event
record_soft_stall() {
    local meta_file="$1"
    local now
    now=$(now_ts)

    local count=$(json_get "$meta_file" '.soft_stall.count // 0')
    local first=$(json_get "$meta_file" '.soft_stall.first_at // empty')

    if [[ -z "$first" ]]; then
        first="$now"
    fi

    json_update "$meta_file" \
        --argjson count $((count + 1)) \
        --argjson first "$first" \
        --argjson last "$now" \
        ".soft_stall = {count: \$count, first_at: \$first, last_at: \$last}"
}

# Record hard stall event
record_hard_stall() {
    local meta_file="$1"
    local now
    now=$(now_ts)

    local count=$(json_get "$meta_file" '.hard_stall.count // 0')
    local first=$(json_get "$meta_file" '.hard_stall.first_at // empty')

    if [[ -z "$first" ]]; then
        first="$now"
    fi

    json_update "$meta_file" \
        --argjson count $((count + 1)) \
        --argjson first "$first" \
        --argjson last "$now" \
        ".hard_stall = {count: \$count, first_at: \$first, last_at: \$last}"
}

# =============================================================================
# Status Transitions
# =============================================================================

# Update status with timestamp
update_status() {
    local meta_file="$1"
    local new_status="$2"
    local now
    now=$(now_ts)

    json_update "$meta_file" \
        --arg status "$new_status" \
        --argjson now "$now" \
        ".status = \$status | .updated_at = \$now"
}
