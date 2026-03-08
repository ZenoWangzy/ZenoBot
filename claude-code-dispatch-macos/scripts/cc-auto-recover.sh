#!/usr/bin/env bash
# cc-auto-recover.sh - Main monitoring script for CC auto-recovery
# Monitors running tasks, detects stalls/errors, and recovers within budgets

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/clock.sh"
source "${SCRIPT_DIR}/lib/json.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/lib/lease.sh"
source "${SCRIPT_DIR}/lib/patterns.sh"
source "${SCRIPT_DIR}/lib/reentrant.sh"
source "${SCRIPT_DIR}/lib/duplicate.sh"
source "${SCRIPT_DIR}/lib/recovery.sh"

# =============================================================================
# Configuration
# =============================================================================

DATA_DIR="${DATA_DIR:-$HOME/.openclaw/workspace/claude-code-dispatch-macos/data}"
MONITOR_INTERVAL=${MONITOR_INTERVAL:-60}  # 1 minute
DRY_RUN=${DRY_RUN:-false}

# =============================================================================
# Main Monitoring Functions
# =============================================================================

# Process a single running task
process_running_task() {
    local run_dir="$1"
    local meta_file="${run_dir}/meta.json"

    if [[ ! -f "$meta_file" ]]; then
        log_debug "No meta.json in $run_dir"
        return 0
    fi

    local task_name=$(json_get "$meta_file" '.task_name // "unknown"')
    local status=$(get_status "$meta_file")
    local run_id=$(basename "$run_dir")

    log_debug "Processing: $task_name (status: $status, run: $run_id)"

    # Skip non-running states
    if [[ "$status" != "running" ]]; then
        return 0
    fi

    # Try to acquire lease
    if ! acquire_lease "$meta_file"; then
        log_debug "Could not acquire lease for $task_name"
        return 0
    fi

    # Check for error patterns in output
    local output_file="${run_dir}/task-output.txt"
    if [[ -f "$output_file" ]]; then
        local output
        output=$(tail -n 100 "$output_file" 2>/dev/null || true)

        local error_type
        error_type=$(detect_error_type "$output") || true

        if [[ -n "$error_type" && "$error_type" != "unknown" ]]; then
            log_warn "Error detected ($error_type): $task_name"

            case "$error_type" in
                fatal)
                    # Fatal error - alert and mark failed
                    send_discord_alert "$task_name" "$run_id" "fatal_error" "$(get_error_summary "$output")"
                    update_status "$meta_file" "failed"
                    clear_lease "$meta_file"
                    return 0
                    ;;
                auth_failure|quota_exhausted)
                    # Special handling - alert only
                    send_discord_alert "$task_name" "$run_id" "$error_type" "$(get_error_summary "$output")"
                    update_status "$meta_file" "failed"
                    clear_lease "$meta_file"
                    return 0
                    ;;
                recoverable)
                    # Try to recover
                    local pattern
                    pattern=$(get_error_pattern "$output")
                    handle_recoverable_error "$meta_file" "$DATA_DIR" "$pattern"
                    clear_lease "$meta_file"
                    return 0
                    ;;
            esac
        fi
    fi

    # Check for hard stall
    if is_hard_stalled "$run_dir"; then
        log_warn "Hard stall detected: $task_name"
        record_hard_stall "$meta_file"
        handle_hard_stall "$meta_file" "$DATA_DIR"
        clear_lease "$meta_file"
        return 0
    fi

    # Check for soft stall
    if is_soft_stalled "$run_dir"; then
        log_warn "Soft stall detected: $task_name"
        record_soft_stall "$meta_file"
        handle_soft_stall "$meta_file" "$DATA_DIR"
        clear_lease "$meta_file"
        return 0
    fi

    # No issues found
    clear_lease "$meta_file"
    return 0
}

# Process queue for stale items
process_queue() {
    local queue_dir="${DATA_DIR}/queue"

    if [[ ! -d "$queue_dir" ]]; then
        return 0
    fi

    for queue_file in "$queue_dir"/*.json; do
        [[ -f "$queue_file" ]] || continue

        local status=$(get_status "$queue_file")

        if [[ "$status" == "queued" ]] && is_worker_dead "$queue_file"; then
            local task_name=$(json_get "$queue_file" '.task_name // "unknown"')
            log_warn "Worker dead detected: $task_name"

            update_status "$queue_file" "worker_dead"
            send_discord_alert "$task_name" "$(basename "$queue_file")" "worker_dead" "Queue item unclaimed > 5 min"
        fi
    done
}

# Check for duplicates
check_duplicates() {
    local running_dir="${DATA_DIR}/running"

    if [[ ! -d "$running_dir" ]]; then
        return 0
    fi

    # Track seen task_names
    declare -A seen_tasks

    for run_dir in "$running_dir"/*/; do
        [[ -d "$run_dir" ]] || continue

        local meta_file="${run_dir}/meta.json"
        [[ -f "$meta_file" ]] || continue

        local task_name=$(json_get "$meta_file" '.task_name // empty')
        [[ -n "$task_name" ]] || continue

        handle_duplicates "$task_name" "$DATA_DIR" "$meta_file"
    done
}

# Cleanup old completed runs
cleanup_old_runs() {
    local done_dir="${DATA_DIR}/done"
    local retention_days=${RETENTION_DAYS:-7}
    local now
    now=$(now_ts)
    local cutoff=$((now - retention_days * 86400))

    if [[ ! -d "$done_dir" ]]; then
        return 0
    fi

    for run_dir in "$done_dir"/*/; do
        [[ -d "$run_dir" ]] || continue

        local meta_file="${run_dir}/meta.json"
        [[ -f "$meta_file" ]] || continue

        local updated_at=$(get_updated_at "$meta_file")

        if [[ -n "$updated_at" && "$updated_at" -lt "$cutoff" ]]; then
            log_info "Cleaning up old run: $(basename "$run_dir")"
            rm -rf "$run_dir"
        fi
    done
}

# =============================================================================
# Main Loop
# =============================================================================

main() {
    log_info "CC Auto-Recovery Monitor starting"
    log_info "DATA_DIR: $DATA_DIR"
    log_info "MONITOR_INTERVAL: ${MONITOR_INTERVAL}s"

    # Ensure directories exist
    mkdir -p "${DATA_DIR}/queue" "${DATA_DIR}/running" "${DATA_DIR}/done" "${DATA_DIR}/.budgets"

    while true; do
        log_debug "Starting monitoring cycle"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would process running tasks"
        else
            # Process running tasks
            for run_dir in "${DATA_DIR}/running"/*/; do
                [[ -d "$run_dir" ]] || continue
                process_running_task "$run_dir"
            done

            # Process queue
            process_queue

            # Check duplicates
            check_duplicates

            # Cleanup old runs
            cleanup_old_runs
        fi

        log_debug "Monitoring cycle complete, sleeping ${MONITOR_INTERVAL}s"
        sleep "$MONITOR_INTERVAL"
    done
}

# =============================================================================
# CLI Interface
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

CC Auto-Recovery Monitor - Monitors and recovers stalled CC tasks

Options:
    -d, --data-dir DIR    Data directory (default: ~/.openclaw/workspace/.../data)
    -i, --interval SEC    Monitoring interval in seconds (default: 60)
    -n, --dry-run         Dry run mode (no actions taken)
    -h, --help            Show this help message

Environment Variables:
    DATA_DIR              Data directory
    MONITOR_INTERVAL      Monitoring interval (seconds)
    DRY_RUN               Set to 'true' for dry run mode
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        -i|--interval)
            MONITOR_INTERVAL="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main
main
