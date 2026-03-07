#!/usr/bin/env bash
# utils.sh - Core utility functions for CC auto-recovery
# Provides logging, JSON helpers (wrapping), ID generation, and path management

set -euo pipefail

# Get script directory for resolving paths
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies (these files must be sourced first)
source "${_LIB_SCRIPT_DIR}/clock.sh"
source "${_LIB_SCRIPT_DIR}/json.sh"

# =============================================================================
# Configuration
# =============================================================================

# Default paths - MUST match design document specification
# DATA_DIR points to the real dispatch data root
DATA_DIR="${DATA_DIR:-$HOME/.openclaw/workspace/claude-code-dispatch-macos/data}"
LOG_FILE="${LOG_FILE:-$HOME/.openclaw/logs/cc-auto-recover.log}"
OWNER_ID="cc-auto-recover@$(hostname)#pid$$"

# Thresholds (from design document)
SOFT_STALL_THRESHOLD=${SOFT_STALL_THRESHOLD:-600}   # 10 minutes
HARD_STALL_THRESHOLD=${HARD_STALL_THRESHOLD:-1200}  # 20 minutes
QUEUE_TIMEOUT=${QUEUE_TIMEOUT:-300}                  # 5 minutes
LEASE_TTL=${LEASE_TTL:-600}                                # 10 minutes

RECOVERY_COOLDOWN_DEFAULT=${RECOVERY_COOLDOWN_DEFAULT:-120}  # 2 minutes

REDISPATCH_COOLDOWN=${REDISPATCH_COOLDOWN:-300}       # 5 minutes

# Budget limits
MAX_CONTINUE_PER_RUN=${MAX_CONTINUE_PER_RUN:-3}
MAX_REDISPATCH_PER_TASK=${MAX_REDISPATCH_PER_TASK:-1}

# Alert cooldown (seconds)
ALERT_COOLDOWN_DEFAULT=${ALERT_COOLDOWN_DEFAULT:-900}  # 15 minutes

AUTH_FAILURE_COOLDOWN=${AUTH_FAILURE_COOLDOWN:-1800}  # 30 minutes
QUOTA_EXHAUSTED_COOLDOWN=${QUOTA_EXHAUSTED_COOLDOWN:-1800}  # 30 minutes

ALERT_COOLDOWN_DIR="${ALERT_COOLDOWN_DIR:-/tmp/cc-alert-cooldown}"
mkdir -p "$ALERT_COOLDOWN_DIR" 2>/dev/null

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local ts
    ts=$(now_ts)
    echo "[$(ts_to_iso "$ts")] [$level] $*" | tee -a "$LOG_FILE"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        log "DEBUG" "$@"
    fi
}

# =============================================================================
# JSON Helpers (using json.sh - already sourced above)
# =============================================================================
# json.sh provides: json_get, json_set, json_update, json_create, json_array_append, json_has
# No need to redefine them here - they are already available from source

# =============================================================================
# ID Generation
# =============================================================================

# Generate unique lease ID with strong randomness
# Format: lease-<timestamp_ns>-<16 bytes hex (32 chars)>
generate_lease_id() {
    local ts
    ts=$(date +%s%N 2>/dev/null || date +%s)000000  # Nanoseconds or seconds + padding
    local random_hex
    # Try to get 16 bytes (32 hex chars) from /dev/urandom
    if [[ -r /dev/urandom ]]; then
        random_hex=$(head -c 16 /dev/urandom | xxd -p 2>/dev/null)
    fi
    # Fallback: use $RANDOM multiple times (less secure but works everywhere)
    if [[ -z "$random_hex" || ${#random_hex} -lt 32 ]]; then
        random_hex=$(printf '%04x%04x%04x%04x%04x%04x%04x%04x' \
            $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM)
    fi
    echo "lease-${ts}-${random_hex}"
}

# Generate unique run ID
generate_run_id() {
    local task_name="${1:-}"
    local random_suffix
    random_suffix=$(head -c 4 /dev/urandom | xxd -p 2>/dev/null || echo "$RANDOM")
    if [[ -n "$task_name" ]]; then
        echo "run-${task_name}-${random_suffix}"
    else
        echo "run-${random_suffix}"
    fi
}

# =============================================================================
# Path Helpers
# =============================================================================

# Get run directory path
get_run_dir() {
    local run_id="$1"
    echo "${DATA_DIR}/running/${run_id}"
}

# Get meta.json path
get_meta_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/meta.json"
}

# Get heartbeat.json path
get_heartbeat_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/heartbeat.json"
}

# Get task-output.txt path
get_output_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/task-output.txt"
}

# Get task-exit-code.txt path
get_exit_code_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/task-exit-code.txt"
}

# Get watcher.pid path
get_watcher_pid_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/watcher.pid"
}

# Get recovery-log.json path
get_recovery_log_path() {
    local run_id="$1"
    echo "$(get_run_dir "$run_id")/recovery-log.json"
}

# Get done directory path for run_id
get_done_dir() {
    local run_id="$1"
    echo "${DATA_DIR}/done/${run_id}"
}

# Get queue file path
get_queue_file_path() {
    local task_name="$1"
    echo "${DATA_DIR}/queue/${task_name}.json"
}

# =============================================================================
# Validation Helpers
# =============================================================================

# Check if run exists
run_exists() {
    local run_id="$1"
    [[ -f "$(get_meta_path "$run_id")" ]]
}

# Check if queue file exists
queue_exists() {
    local task_name="$1"
    [[ -f "$(get_queue_file_path "$task_name")" ]]
}

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}
