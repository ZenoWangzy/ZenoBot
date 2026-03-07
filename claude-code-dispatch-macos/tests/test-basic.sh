#!/usr/bin/env bash
# test-basic.sh - Basic tests for CC auto-recovery system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/scripts/lib"

# Test helpers
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_start() {
    echo "Testing: $1"
    ((TESTS_RUN++)) || true
}

test_pass() {
    echo "  ✓ PASS"
    ((TESTS_PASSED++)) || true
}

test_fail() {
    echo "  ✗ FAIL: $1"
    ((TESTS_FAILED++)) || true
}

# =============================================================================
# Test: Library files exist
# =============================================================================
test_libraries_exist() {
    test_start "Library files exist"

    local libs=(
        "utils.sh"
        "clock.sh"
        "json.sh"
        "state.sh"
        "lease.sh"
        "patterns.sh"
        "reentrant.sh"
        "duplicate.sh"
        "recovery.sh"
    )

    local all_exist=true
    for lib in "${libs[@]}"; do
        if [[ ! -f "${LIB_DIR}/${lib}" ]]; then
            test_fail "Missing: ${lib}"
            all_exist=false
        fi
    done

    if $all_exist; then
        test_pass
    fi
}

# =============================================================================
# Test: clock.sh functions
# =============================================================================
test_clock_functions() {
    test_start "clock.sh functions"

    source "${LIB_DIR}/clock.sh"

    # Test now_ts
    local ts
    ts=$(now_ts)
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        echo "    now_ts: OK"
    else
        test_fail "now_ts returned non-integer: $ts"
        return
    fi

    # Test format_ts
    local formatted
    formatted=$(format_ts "$ts")
    if [[ -n "$formatted" ]]; then
        echo "    format_ts: OK"
    else
        test_fail "format_ts returned empty"
        return
    fi

    # Test ts_diff
    local diff
    ts1=$(now_ts)
    sleep 1
    ts2=$(now_ts)
    diff=$(ts_diff "$ts1" "$ts2")
    if [[ "$diff" -ge 1 ]]; then
        echo "    ts_diff: OK"
    else
        test_fail "ts_diff returned unexpected value: $diff"
        return
    fi

    test_pass
}

# =============================================================================
# Test: json.sh functions
# =============================================================================
test_json_functions() {
    test_start "json.sh functions"

    source "${LIB_DIR}/json.sh"

    # Create test JSON file
    local test_file="/tmp/test-json-$$.json"
    echo '{"name": "test", "count": 42}' > "$test_file"

    # Test json_get
    local name
    name=$(json_get "$test_file" '.name')
    if [[ "$name" == "test" ]]; then
        echo "    json_get: OK"
    else
        test_fail "json_get returned: $name"
        rm -f "$test_file"
        return
    fi

    # Test json_set
    json_set "$test_file" '.name' "updated"
    name=$(json_get "$test_file" '.name')
    if [[ "$name" == "updated" ]]; then
        echo "    json_set: OK"
    else
        test_fail "json_set failed"
        rm -f "$test_file"
        return
    fi

    # Test json_update
    json_update "$test_file" --arg new "value" '.new_field = $new'
    local new_val
    new_val=$(json_get "$test_file" '.new_field')
    if [[ "$new_val" == "value" ]]; then
        echo "    json_update: OK"
    else
        test_fail "json_update failed"
        rm -f "$test_file"
        return
    fi

    rm -f "$test_file"
    test_pass
}

# =============================================================================
# Test: patterns.sh functions
# =============================================================================
test_patterns_functions() {
    test_start "patterns.sh functions"

    source "${LIB_DIR}/patterns.sh"

    # Test recoverable error detection
    local pattern
    pattern=$(is_recoverable_error "Error: ECONNREFUSED") || true
    if [[ -n "$pattern" ]]; then
        echo "    is_recoverable_error: OK"
    else
        test_fail "is_recoverable_error failed to detect ECONNREFUSED"
        return
    fi

    # Test fatal error detection
    pattern=$(is_fatal_error "Error: authentication failed") || true
    if [[ -n "$pattern" ]]; then
        echo "    is_fatal_error: OK"
    else
        test_fail "is_fatal_error failed to detect auth failure"
        return
    fi

    # Test detect_error_type
    local error_type
    error_type=$(detect_error_type "Error: ECONNREFUSED") || true
    if [[ "$error_type" == "recoverable" ]]; then
        echo "    detect_error_type: OK"
    else
        test_fail "detect_error_type returned: $error_type"
        return
    fi

    test_pass
}

# =============================================================================
# Test: utils.sh functions
# =============================================================================
test_utils_functions() {
    test_start "utils.sh functions"

    source "${LIB_DIR}/utils.sh"

    # Test generate_run_id
    local run_id
    run_id=$(generate_run_id)
    if [[ "$run_id" =~ ^run-[a-f0-9]+$ ]]; then
        echo "    generate_run_id: OK"
    else
        test_fail "generate_run_id returned unexpected format: $run_id"
        return
    fi

    # Test generate_lease_id
    local lease_id
    lease_id=$(generate_lease_id)
    if [[ "$lease_id" =~ ^lease-[0-9]+-[a-f0-9]+$ ]]; then
        echo "    generate_lease_id: OK"
    else
        test_fail "generate_lease_id returned unexpected format: $lease_id"
        return
    fi

    test_pass
}

# =============================================================================
# Test: state.sh functions
# =============================================================================
test_state_functions() {
    test_start "state.sh functions"

    source "${LIB_DIR}/clock.sh"
    source "${LIB_DIR}/json.sh"
    source "${LIB_DIR}/utils.sh"
    source "${LIB_DIR}/state.sh"

    # Create test meta.json
    local test_dir="/tmp/test-state-$$"
    mkdir -p "$test_dir"
    local test_file="${test_dir}/meta.json"

    local now
    now=$(now_ts)

    jq -n \
        --arg status "running" \
        --argjson now "$now" \
        '{
            status: $status,
            created_at: $now,
            started_at: $now,
            updated_at: $now
        }' > "$test_file"

    # Test get_status
    local status
    status=$(get_status "$test_file")
    if [[ "$status" == "running" ]]; then
        echo "    get_status: OK"
    else
        test_fail "get_status returned: $status"
        rm -rf "$test_dir"
        return
    fi

    # Test is_active_status
    if is_active_status "running"; then
        echo "    is_active_status: OK"
    else
        test_fail "is_active_status failed for 'running'"
        rm -rf "$test_dir"
        return
    fi

    rm -rf "$test_dir"
    test_pass
}

# =============================================================================
# Test: lease.sh functions
# =============================================================================
test_lease_functions() {
    test_start "lease.sh functions"

    source "${LIB_DIR}/clock.sh"
    source "${LIB_DIR}/json.sh"
    source "${LIB_DIR}/utils.sh"
    source "${LIB_DIR}/lease.sh"

    # Create test meta.json
    local test_dir="/tmp/test-lease-$$"
    mkdir -p "$test_dir"
    local test_file="${test_dir}/meta.json"

    jq -n '{}' > "$test_file"

    # Test acquire_lease
    if acquire_lease "$test_file"; then
        echo "    acquire_lease: OK"
    else
        test_fail "acquire_lease failed"
        rm -rf "$test_dir"
        return
    fi

    # Test lease_is_valid
    if lease_is_valid "$test_file"; then
        echo "    lease_is_valid: OK"
    else
        test_fail "lease_is_valid returned false after acquire"
        rm -rf "$test_dir"
        return
    fi

    # Test clear_lease
    clear_lease "$test_file"
    if ! lease_is_valid "$test_file"; then
        echo "    clear_lease: OK"
    else
        test_fail "clear_lease did not clear the lease"
        rm -rf "$test_dir"
        return
    fi

    rm -rf "$test_dir"
    test_pass
}

# =============================================================================
# Run all tests
# =============================================================================
main() {
    echo "==================================="
    echo "  CC Auto-Recovery Basic Tests"
    echo "==================================="
    echo ""

    test_libraries_exist
    test_clock_functions
    test_json_functions
    test_patterns_functions
    test_utils_functions
    test_state_functions
    test_lease_functions

    echo ""
    echo "==================================="
    echo "  Test Results"
    echo "==================================="
    echo "  Total:  $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "==================================="

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
