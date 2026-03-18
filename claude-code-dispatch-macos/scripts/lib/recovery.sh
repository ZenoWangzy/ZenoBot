#!/usr/bin/env bash
# recovery.sh - Recovery actions for CC auto-recovery
# Implements continue, re_dispatch, and hard stall detection

set -euo pipefail

# Get script directory
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_SCRIPT_DIR}/utils.sh"
source "${_LIB_SCRIPT_DIR}/clock.sh"
source "${_LIB_SCRIPT_DIR}/json.sh"
source "${_LIB_SCRIPT_DIR}/state.sh"
source "${_LIB_SCRIPT_DIR}/lease.sh"
source "${_LIB_SCRIPT_DIR}/patterns.sh"
source "${_LIB_SCRIPT_DIR}/reentrant.sh"

# =============================================================================
# Budget Configuration
# =============================================================================

MAX_CONTINUE_PER_RUN=${MAX_CONTINUE_PER_RUN:-3}
MAX_REDISPATCH_PER_TASK=${MAX_REDISPATCH_PER_TASK:-1}
RECOVERY_COOLDOWN=${RECOVERY_COOLDOWN:-300}  # 5 minutes

# =============================================================================
# Budget Tracking
# =============================================================================

# Get continue count for a run
get_continue_count() {
    local meta_file="$1"
    json_get "$meta_file" '.recovery.continue_count // 0'
}

# Get redispatch count for a task (by task_name)
get_redispatch_count() {
    local task_name="$1"
    local data_dir="$2"
    local count_file="${data_dir}/.budgets/${task_name}.json"

    if [[ -f "$count_file" ]]; then
        json_get "$count_file" '.redispatch_count // 0'
    else
        echo 0
    fi
}

# Increment continue count
increment_continue_count() {
    local meta_file="$1"
    local now
    now=$(now_ts)

    local count=$(get_continue_count "$meta_file")
    count=$((count + 1))

    json_update "$meta_file" \
        --argjson count "$count" \
        --argjson now "$now" \
        '.recovery.continue_count = $count | .recovery.last_continue_at = $now'
}

# Increment redispatch count
increment_redispatch_count() {
    local task_name="$1"
    local data_dir="$2"
    local budget_dir="${data_dir}/.budgets"

    mkdir -p "$budget_dir"
    local count_file="${budget_dir}/${task_name}.json"

    local count=0
    if [[ -f "$count_file" ]]; then
        count=$(json_get "$count_file" '.redispatch_count // 0')
    fi
    count=$((count + 1))

    local now
    now=$(now_ts)

    json_update "$count_file" \
        --argjson count "$count" \
        --argjson now "$now" \
        '.redispatch_count = $count | .last_redispatch_at = $now' 2>/dev/null || \
    jq -n --argjson count "$count" --argjson now "$now" \
        '{redispatch_count: $count, last_redispatch_at: $now}' > "$count_file"
}

# Check if continue budget available
can_continue() {
    local meta_file="$1"
    local count=$(get_continue_count "$meta_file")
    [[ $count -lt $MAX_CONTINUE_PER_RUN ]]
}

# Check if redispatch budget available
can_redispatch() {
    local task_name="$1"
    local data_dir="$2"
    local count=$(get_redispatch_count "$task_name" "$data_dir")
    [[ $count -lt $MAX_REDISPATCH_PER_TASK ]]
}

# =============================================================================
# Cooldown Check
# =============================================================================

# Check if in cooldown period
is_in_cooldown() {
    local meta_file="$1"
    local now
    now=$(now_ts)

    local last_recovery=$(json_get "$meta_file" '.recovery.last_action_at // 0')

    if [[ -n "$last_recovery" && $((now - last_recovery)) -lt $RECOVERY_COOLDOWN ]]; then
        return 0  # In cooldown
    fi
    return 1  # Not in cooldown
}

# =============================================================================
# Recovery Actions
# =============================================================================

# Execute continue action (send to tmux session)
execute_continue() {
    local meta_file="$1"
    local run_dir
    run_dir=$(dirname "$meta_file")

    local tmux_session=$(json_get "$meta_file" '.tmux_session // empty')

    if [[ -z "$tmux_session" ]]; then
        log_error "No tmux session for continue action"
        return 1
    fi

    # Check tmux session exists
    if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
        log_error "Tmux session not found: $tmux_session"
        return 1
    fi

    # Send continue message
    log_info "Sending continue to tmux session: $tmux_session"
    tmux send-keys -t "$tmux_session" "continue" Enter

    # Update metadata
    local now
    now=$(now_ts)
    increment_continue_count "$meta_file"
    json_update "$meta_file" \
        --argjson now "$now" \
        '.recovery.last_action_at = $now | .recovery.last_action = "continue"'

    return 0
}

# Execute re_dispatch action (create new run from original task)
execute_redispatch() {
    local meta_file="$1"
    local data_dir="$2"

    local task_name=$(json_get "$meta_file" '.task_name // empty')
    local original_prompt=$(json_get "$meta_file" '.original_prompt // empty')

    if [[ -z "$task_name" || -z "$original_prompt" ]]; then
        log_error "Missing task_name or original_prompt for redispatch"
        return 1
    fi

    # Check reentrant safety
    local reentrant_class
    reentrant_class=$(can_re_dispatch "$meta_file") || true

    if [[ "$reentrant_class" == "class_c" ]]; then
        log_error "Task is Class C (not safe for redispatch): $task_name"
        return 1
    fi

    # Create new queue entry
    local now
    now=$(now_ts)
    local queue_file="${data_dir}/queue/${task_name}-redispatch-${now}.json"

    log_info "Creating redispatch queue entry: $queue_file"

    jq -n \
        --arg task_name "$task_name" \
        --arg prompt "$original_prompt" \
        --argjson now "$now" \
        --arg source_run "$(basename "$run_dir")" \
        '{
            task_name: $task_name,
            original_prompt: $prompt,
            status: "queued",
            created_at: $now,
            source: "redispatch",
            source_run: $source_run
        }' > "$queue_file"

    # Update budget
    increment_redispatch_count "$task_name" "$data_dir"

    # Update original run metadata
    json_update "$meta_file" \
        --argjson now "$now" \
        '.recovery.last_action_at = $now | .recovery.last_action = "redispatch"'

    return 0
}

# =============================================================================
# Hard Stall Handler
# =============================================================================

# Handle hard stall (alert and optionally recover)
handle_hard_stall() {
    local meta_file="$1"
    local data_dir="$2"
    local run_id=$(basename "$(dirname "$meta_file")")
    local task_name=$(json_get "$meta_file" '.task_name // "unknown"')

    log_warn "Hard stall detected: $task_name (run: $run_id)"

    # Record hard stall
    record_hard_stall "$meta_file"

    # Check if safe to recover
    local reentrant_class
    reentrant_class=$(can_re_dispatch "$meta_file") || true

    if [[ "$reentrant_class" == "class_c" ]]; then
        # Not safe for redispatch - just alert
        log_error "Hard stall not recoverable (Class C): $task_name"
        send_discord_alert "$task_name" "$run_id" "hard_stall_unrecoverable" "Task is not safe for re-dispatch"
        update_status "$meta_file" "failed"
        return 1
    fi

    # Check redispatch budget
    if can_redispatch "$task_name" "$data_dir"; then
        log_info "Attempting redispatch for hard stall: $task_name"
        if execute_redispatch "$meta_file" "$data_dir"; then
            send_discord_alert "$task_name" "$run_id" "hard_stall_recovering" "Attempting re-dispatch"
            update_status "$meta_file" "recovering"
            return 0
        else
            log_error "Redispatch failed for hard stall: $task_name"
            send_discord_alert "$task_name" "$run_id" "hard_stall_redispatch_failed" "Re-dispatch failed"
            update_status "$meta_file" "failed"
            return 1
        fi
    else
        # Budget exhausted
        log_error "Redispatch budget exhausted for: $task_name"
        send_discord_alert "$task_name" "$run_id" "hard_stall_budget_exhausted" "Re-dispatch budget exhausted"
        update_status "$meta_file" "retry_exhausted"
        return 1
    fi
}

# =============================================================================
# Soft Stall Handler
# =============================================================================

# Handle soft stall (try continue first)
handle_soft_stall() {
    local meta_file="$1"
    local data_dir="$2"
    local run_id=$(basename "$(dirname "$meta_file")")
    local task_name=$(json_get "$meta_file" '.task_name // "unknown"')

    log_warn "Soft stall detected: $task_name (run: $run_id)"

    # Record soft stall
    record_soft_stall "$meta_file"

    # Check cooldown
    if is_in_cooldown "$meta_file"; then
        log_debug "In cooldown period, skipping recovery: $task_name"
        return 0
    fi

    # Check continue budget
    if can_continue "$meta_file"; then
        log_info "Attempting continue for soft stall: $task_name"
        if execute_continue "$meta_file"; then
            send_discord_alert "$task_name" "$run_id" "soft_stall_recovering" "Attempting continue"
            return 0
        else
            log_warn "Continue failed for soft stall: $task_name"
        fi
    fi

    # Continue exhausted, try redispatch if safe
    local reentrant_class
    reentrant_class=$(can_re_dispatch "$meta_file") || true

    if [[ "$reentrant_class" != "class_c" ]] && can_redispatch "$task_name" "$data_dir"; then
        log_info "Attempting redispatch for soft stall: $task_name"
        if execute_redispatch "$meta_file" "$data_dir"; then
            send_discord_alert "$task_name" "$run_id" "soft_stall_redispatch" "Continue exhausted, attempting re-dispatch"
            update_status "$meta_file" "recovering"
            return 0
        fi
    fi

    # Cannot recover
    log_error "Cannot recover soft stall: $task_name"
    return 1
}

# =============================================================================
# Recoverable Error Handler
# =============================================================================

# Handle recoverable error
handle_recoverable_error() {
    local meta_file="$1"
    local data_dir="$2"
    local error_pattern="$3"
    local run_id=$(basename "$(dirname "$meta_file")")
    local task_name=$(json_get "$meta_file" '.task_name // "unknown"')

    log_warn "Recoverable error detected: $error_pattern (task: $task_name)"

    # Update status
    update_status "$meta_file" "recoverable_error"

    # Check cooldown
    if is_in_cooldown "$meta_file"; then
        log_debug "In cooldown period, skipping recovery: $task_name"
        return 0
    fi

    # Try continue first
    if can_continue "$meta_file"; then
        log_info "Attempting continue for recoverable error: $task_name"
        if execute_continue "$meta_file"; then
            update_status "$meta_file" "recovering"
            send_discord_alert "$task_name" "$run_id" "error_recovering" "Recoverable error: $error_pattern"
            return 0
        fi
    fi

    # Fallback to redispatch
    local reentrant_class
    reentrant_class=$(can_re_dispatch "$meta_file") || true

    if [[ "$reentrant_class" != "class_c" ]] && can_redispatch "$task_name" "$data_dir"; then
        log_info "Attempting redispatch for recoverable error: $task_name"
        if execute_redispatch "$meta_file" "$data_dir"; then
            update_status "$meta_file" "recovering"
            send_discord_alert "$task_name" "$run_id" "error_redispatch" "Re-dispatch after error: $error_pattern"
            return 0
        fi
    fi

    # Cannot recover
    log_error "Cannot recover from error: $task_name"
    send_discord_alert "$task_name" "$run_id" "error_unrecoverable" "Cannot recover from: $error_pattern"
    update_status "$meta_file" "retry_exhausted"
    return 1
}
