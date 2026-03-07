#!/usr/bin/env bash
# duplicate.sh - Duplicate detection for CC auto-recovery
# Implements three-tier classification: benign, suppressible, dangerous

# Based on design document Section 6

set -euo pipefail

# Get script directory
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_SCRIPT_DIR}/utils.sh"
source "${_LIB_SCRIPT_DIR}/clock.sh"
source "${_LIB_SCRIPT_DIR}/json.sh"
source "${_LIB_SCRIPT_DIR}/state.sh"
source "${_LIB_SCRIPT_DIR}/lease.sh"

# =============================================================================
# Duplicate Detection
# =============================================================================

# Find duplicate runs by task_name
# Returns list of meta.json paths (one per line)
find_duplicates() {
    local task_name="$1"
    local data_dir="$2"

    # Guard: skip if directories don't exist
    [[ -d "${data_dir}/running" ]] || return 0
    [[ -d "${data_dir}/queue" ]] || return 0

    local duplicates=()

    # Check queue files
    if [[ -d "${data_dir}/queue" ]]; then
        for queue_file in "${data_dir}/queue"/*.json; do
            [[ -f "$queue_file" ]] || continue
            local meta
            meta=$(json_get "$queue_file" '.task_name // empty')
            [[ "$meta" == "$task_name" ]] && duplicates+=("$queue_file")
        done
    fi

    # Check running dirs
    for dir in "${data_dir}/running"/*/; do
        [[ -d "$dir" ]] || continue

        local meta_file="${dir}/meta.json"
        [[ -f "$meta_file" ]] || continue

        local meta
        meta=$(json_get "$meta_file" '.task_name // empty')
        [[ "$meta" == "$task_name" ]] && duplicates+=("$meta_file")
    done

    # Return all duplicate meta.json paths
    printf '%s\n' "${duplicates[@]}"
}

# Classify duplicate type
# Three-tier: benign, suppressible, dangerous
classify_duplicate() {
    local files=("$@")
    local dup_count=${#files[@]}

    [[ $dup_count -le 1 ]] && { echo "none"; return 0; }

    local active_count=0
    local valid_lease_count=0
    local active_writers=()

    for f in "${files[@]}"; do
        local status=$(get_status "$f")
        local lease_info
        lease_info=$(json_get "$f" '.lease // empty')

        # Count active (running/recovering)
        if [[ "$status" =~ ^(running|recovering)$ ]]; then
            ((active_count++))
        fi

        if lease_is_valid "$f" && [[ -n "$lease_info" ]]; then
            ((valid_lease_count++))
        fi

        # Check for active writers (recent output modification)
        local dir=$(dirname "$f")
        local output_file="${dir}/task-output.txt"
        if [[ -f "$output_file" ]]; then
            local now
            now=$(now_ts)
            local mtime
            mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null || echo 0)
            if [[ $((now - mtime)) -lt 300 ]]; then
                active_writers+=("$f")
            fi
        fi
    done

    # Determine classification
    if [[ $valid_lease_count -ge 2 ]]; then
        echo "dangerous"
    elif [[ ${#active_writers[@]} -ge 2 ]]; then
        echo "dangerous"
    elif [[ $active_count -eq 2 && $valid_lease_count -eq 1 ]]; then
        echo "suppressible"
    else
        echo "benign"
    fi
}

# Determine which run to suppress
# Precedence: 1. Valid lease holder wins
#                2. Active writer wins
#                3. Start time fallback (never suppress based solely on start_time)
#                4. Run ID tiebreaker (lexicographically)
pick_suppress_target() {
    local files=("$@")
    local winner=""
    local winner_start=0
    local winner_has_lease=false
    local winner_is_writer=false

    for f in "${files[@]}"; do
        local has_lease=false
        local is_writer=false
        local start_time=$(json_get "$f" '.started_at // .created_at // 0')

        # Check lease
        if lease_is_valid "$f"; then
            has_lease=true
        fi

        # Check active writer
        local run_dir=$(dirname "$f")
        local output_file="${run_dir}/task-output.txt"
        if [[ -f "$output_file" ]]; then
            local now
            now=$(now_ts)
            local mtime
            mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null || echo 0)
            if [[ $((now - mtime)) -lt 300 ]]; then
                is_writer=true
            fi
        fi

        # Precedence logic
        if [[ -z "$winner" ]]; then
            winner="$f"
            winner_start="$start_time"
            winner_has_lease="$has_lease"
            winner_is_writer="$is_writer"
        elif [[ "$has_lease" == "true" && "$winner_has_lease" == "false" ]]; then
            winner="$f"
            winner_start="$start_time"
            winner_has_lease="$has_lease"
            winner_is_writer="$is_writer"
        elif [[ "$has_lease" == "$winner_has_lease" && "$is_writer" == "true" && "$winner_is_writer" == "false" ]]; then
            winner="$f"
            winner_start="$start_time"
            winner_has_lease="$has_lease"
            winner_is_writer="$is_writer"
        elif [[ "$has_lease" == "$winner_has_lease" && "$is_writer" == "$winner_is_writer" ]]; then
            # Fallback: earlier start_time wins (we want to suppress older runs)
            if [[ "$start_time" -lt "$winner_start" ]]; then
                winner="$f"
                winner_start="$start_time"
                winner_has_lease="$has_lease"
                winner_is_writer="$is_writer"
            fi
        fi
    done

    # Return all files except the winner (these should be suppressed)
    for f in "${files[@]}"; do
        if [[ "$f" != "$winner" ]]; then
            echo "$f"
        fi
    done
}

# Suppress a run
suppress_run() {
    local meta_file="$1"
    local reason="$2"
    local now
    now=$(now_ts)

    json_update "$meta_file" \
        --arg status "suppressed" \
        --arg reason "$reason" \
        --argjson now "$now" \
        ".status = \$status | .suppressed_at = \$now | .suppressed_reason = \$reason"

    log_info "Suppressed run: $meta_file (reason: $reason)"
}

# Check for and handle duplicates
# Returns: 0 = handled, 1 = no duplicates
handle_duplicates() {
    local task_name="$1"
    local data_dir="$2"
    local meta_file="$3"

    # Find duplicates
    local duplicates
    mapfile -t duplicates < <(find_duplicates "$task_name" "$data_dir")

    local dup_count=${#duplicates[@]}

    [[ $dup_count -le 1 ]] && return 1

    # Classify
    local dup_type
    dup_type=$(classify_duplicate "${duplicates[@]}")

    log_warn "Duplicate detected ($dup_type): $task_name"

    case "$dup_type" in
        dangerous)
            # Alert on dangerous duplicate
            send_discord_alert "$task_name" "$(basename "$meta_file")" "dangerous_duplicate" "Multiple active runs detected"
            return 0
            ;;
        suppressible)
            # Suppress older runs
            local to_suppress
            mapfile -t to_suppress < <(pick_suppress_target "${duplicates[@]}")
            for f in "${to_suppress[@]}"; do
                suppress_run "$f" "duplicate"
            done
            ;;
        benign)
            # Just log
            log_debug "Benign duplicate: $task_name"
            ;;
    esac

    return 0
}
