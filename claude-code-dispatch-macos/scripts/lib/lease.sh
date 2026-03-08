#!/usr/bin/env bash
# lease.sh - Lease management for CC auto-recovery
# Implements write-then-verify pattern for concurrent safety

set -euo pipefail

# Get script directory
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_SCRIPT_DIR}/utils.sh"
source "${_LIB_SCRIPT_DIR}/clock.sh"
source "${_LIB_SCRIPT_DIR}/json.sh"

# Configuration
LEASE_TTL=${LEASE_TTL:-600}  # 10 minutes
LEASE_RENEWAL_THRESHOLD=${LEASE_RENEWAL_THRESHOLD:-120}  # 2 minutes
LEASE_LOCK_DIR="${LEASE_LOCK_DIR:-/tmp/cc-lease-locks}"  # Directory for atomic locks

# Ensure lock directory exists
mkdir -p "$LEASE_LOCK_DIR" 2>/dev/null || true

# =============================================================================
# Lease Validation
# =============================================================================

# Check if lease is valid (not expired, exists)
lease_is_valid() {
    local meta_file="$1"
    local now
    now=$(now_ts)

    # Check if lease exists
    local lease_holder=$(json_get "$meta_file" '.lease.holder // empty')
    [[ -z "$lease_holder" ]] && return 1

    # Check expiration
    local expires_at=$(json_get "$meta_file" '.lease.expires_at // 0')
    [[ "$expires_at" -lt "$now" ]] && return 1

    return 0
}

# Check if we own the lease
lease_is_owner() {
    local meta_file="$1"
    local expected_owner="${2:-$OWNER_ID}"

    local lease_holder=$(json_get "$meta_file" '.lease.holder // empty')
    [[ "$lease_holder" == "$expected_owner" ]]
}

# Get remaining lease time in seconds
lease_remaining_time() {
    local meta_file="$1"
    local now
    now=$(now_ts)

    local expires_at=$(json_get "$meta_file" '.lease.expires_at // 0')
    local remaining=$((expires_at - now))

    [[ $remaining -lt 0 ]] && remaining=0
    echo "$remaining"
}

# =============================================================================
# Lease Acquisition
# =============================================================================

# Acquire lease with mkdir atomic lock + write-then-verify pattern
# Returns: 0 = acquired, 1 = failed
acquire_lease() {
    local meta_file="$1"
    local lease_id="${2:-$(generate_lease_id)}"
    local now
    now=$(now_ts)
    local expires=$((now + LEASE_TTL))

    # Create unique lock directory path for this meta file
    local meta_hash
    meta_hash=$(echo "$meta_file" | shasum -a 256 | cut -c1-16)
    local lock_dir="${LEASE_LOCK_DIR}/${meta_hash}"

    # Phase 1: Acquire atomic lock using mkdir (POSIX atomic operation)
    if ! mkdir "$lock_dir" 2>/dev/null; then
        log_debug "Lock directory exists, another process has lock: $lock_dir"
        return 1
    fi

    # Ensure we release lock on exit
    trap "rmdir '$lock_dir' 2>/dev/null || true" RETURN

    # Phase 2: Check if already owned (inside lock)
    if lease_is_owner "$meta_file"; then
        return 0
    fi

    # Check if lease is valid (held by someone else)
    if lease_is_valid "$meta_file"; then
        log_debug "Lease held by another owner: $meta_file"
        return 1
    fi

    # Phase 3: Write lease (inside lock)
    json_update "$meta_file" \
        --arg holder "$lease_id" \
        --argjson now "$now" \
        --argjson expires "$expires" \
        ".lease = {holder: \$holder, acquired_at: \$now, expires_at: \$expires}"

    # Phase 4: Verify write (write-then-verify pattern, still inside lock)
    local verify_holder
    verify_holder=$(json_get "$meta_file" '.lease.holder // empty')
    if [[ "$verify_holder" != "$lease_id" ]]; then
        log_warn "Lease acquisition failed (verification mismatch): $meta_file"
        return 1
    fi

    log_debug "Lease acquired: $meta_file (expires in ${LEASE_TTL}s)"

    # Lock will be released by trap on function return
    return 0
}

# Verify lease is still held
verify_lease() {
    local meta_file="$1"
    local expected_owner="${2:-$OWNER_ID}"

    if ! lease_is_valid "$meta_file"; then
        return 1
    fi

    lease_is_owner "$meta_file" "$expected_owner"
}

# =============================================================================
# Lease Management
# =============================================================================

# Renew lease if we own it
renew_lease() {
    local meta_file="$1"
    local current_lease_id="${2:-$OWNER_ID}"

    # Check ownership
    if ! lease_is_owner "$meta_file" "$current_lease_id"; then
        log_warn "Cannot renew lease: not owner"
        return 1
    fi

    # Check if renewal needed
    local remaining
    remaining=$(lease_remaining_time "$meta_file")

    if [[ "$remaining" -gt "$LEASE_RENEWAL_THRESHOLD" ]]; then
        log_debug "Lease renewal not needed yet: $remaining seconds remaining"
        return 0
    fi

    # Renew lease
    local now
    now=$(now_ts)
    local new_expires=$((now + LEASE_TTL))

    json_update "$meta_file" \
        --argjson expires "$new_expires" \
        ".lease.expires_at = \$expires"

    # Verify renewal
    local verify_expires=$(json_get "$meta_file" '.lease.expires_at')
    if [[ "$verify_expires" != "$new_expires" ]]; then
        log_warn "Lease renewal failed: verification mismatch"
        return 1
    fi

    log_debug "Lease renewed until $(ts_to_iso $new_expires)"
    return 0
}

# Renew lease if needed (convenience wrapper)
renew_lease_if_needed() {
    local meta_file="$1"
    local current_lease_id="$2"

    remaining=$(lease_remaining_time "$meta_file")

    if [[ "$remaining" -gt 0 && "$remaining" -lt "$LEASE_RENEWAL_THRESHOLD" ]]; then
        renew_lease "$meta_file" "$current_lease_id"
    fi
}

# Clear lease
clear_lease() {
    local meta_file="$1"
    json_update "$meta_file" '.lease = null'
    log_debug "Lease cleared: $meta_file"
}

# Clear lease if we own it
clear_lease_if_owner() {
    local meta_file="$1"
    local expected_owner="$2"

    if lease_is_owner "$meta_file" "$expected_owner"; then
        clear_lease "$meta_file"
    fi
}
