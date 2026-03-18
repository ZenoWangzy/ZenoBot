#!/usr/bin/env bash
# patterns.sh - Error pattern detection for CC auto-recovery
# Detects recoverable and fatal error patterns in task output

set -euo pipefail

# Get script directory
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_SCRIPT_DIR}/utils.sh"

# =============================================================================
# Error Pattern Definitions
# =============================================================================

# Recoverable patterns (can auto-continue)
# These are transient errors that can be resolved by retrying
RECOVERABLE_PATTERNS=(
    "unable to connect"
    "API unconnected"
    "ECONNREFUSED"
    "ETIMEDOUT"
    "network error"
    "session expired"
    "connection refused"
    "failed to fetch"
    "request timeout"
    "temporary failure"
    "503 Service Unavailable"
    "502 Bad Gateway"
    "504 Gateway Timeout"
    "reset by peer"
    "connection reset"
)

# Fatal patterns (direct alert, no recovery)
# These are fundamental errors that require human intervention
FATAL_PATTERNS=(
    "cannot be launched inside another Claude Code session"
    "unrecognized arguments"
    "requires a valid session ID"
    "authentication failed"
    "invalid API key"
    "quota exceeded"
    "fatal error"
    "permission denied"
    "access denied"
    "configuration error"
    "invalid configuration"
    "missing required"
    "not found"
    "no such file"
)

# Auth failure patterns (special handling)
AUTH_FAILURE_PATTERNS=(
    "authentication failed"
    "invalid API key"
    "unauthorized"
    "login required"
    "not authenticated"
)

# Quota exhaustion patterns (special handling)
QUOTA_EXHAUSTED_PATTERNS=(
    "quota exceeded"
    "rate limit"
    "too many requests"
    "usage limit"
)

# =============================================================================
# Pattern Detection Functions
# =============================================================================

# Check if output matches recoverable pattern
# Returns: pattern name if found, exit 1 if not
is_recoverable_error() {
    local output="$1"

    for pattern in "${RECOVERABLE_PATTERNS[@]}"; do
        if echo "$output" | grep -qi "$pattern"; then
            echo "$pattern"
            return 0
        fi
    done

    return 1
}

# Check if output matches fatal pattern
# Returns: pattern name if found, exit 1 if not
is_fatal_error() {
    local output="$1"

    for pattern in "${FATAL_PATTERNS[@]}"; do
        if echo "$output" | grep -qi "$pattern"; then
            echo "$pattern"
            return 0
        fi
    done

    return 1
}

# Check if output matches auth failure pattern
# Returns: pattern name if found, exit 1 if not
is_auth_failure() {
    local output="$1"

    for pattern in "${AUTH_FAILURE_PATTERNS[@]}"; do
        if echo "$output" | grep -qi "$pattern"; then
            echo "$pattern"
            return 0
        fi
    done

    return 1
}

# Check if output matches quota exhaustion pattern
# Returns: pattern name if found, exit 1 if not
is_quota_exhausted() {
    local output="$1"

    for pattern in "${QUOTA_EXHAUSTED_PATTERNS[@]}"; do
        if echo "$output" | grep -qi "$pattern"; then
            echo "$pattern"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# Error Type Classification
# =============================================================================

# Detect error type
# Returns: fatal, recoverable, auth_failure, quota_exhausted, or unknown
detect_error_type() {
    local output="$1"

    # Check fatal first (highest priority)
    if is_fatal_error "$output" >/dev/null 2>&1; then
        echo "fatal"
        return 0
    fi

    # Check auth failure (special handling)
    if is_auth_failure "$output" >/dev/null 2>&1; then
        echo "auth_failure"
        return 0
    fi

    # Check quota exhaustion (special handling)
    if is_quota_exhausted "$output" >/dev/null 2>&1; then
        echo "quota_exhausted"
        return 0
    fi

    # Check recoverable
    if is_recoverable_error "$output" >/dev/null 2>&1; then
        echo "recoverable"
        return 0
    fi

    echo "unknown"
    return 1
}

# Get error pattern name
# Returns the first matching pattern name
get_error_pattern() {
    local output="$1"

    # Check each category and priority order
    local pattern
    pattern=$(is_fatal_error "$output") && { echo "fatal:$pattern"; return; }
    pattern=$(is_auth_failure "$output") && { echo "auth_failure:$pattern"; return; }
    pattern=$(is_quota_exhausted "$output") && { echo "quota_exhausted:$pattern"; return; }
    pattern=$(is_recoverable_error "$output") && { echo "recoverable:$pattern"; return; }

    echo "unknown"
}

# =============================================================================
# Error Summary
# =============================================================================

# Get error summary for alerting
get_error_summary() {
    local output="$1"
    local max_lines="${2:-5}"

    # Get last N lines
    local tail_output
    tail_output=$(echo "$output" | tail -n "$max_lines")

    # Truncate to 500 chars max
    if [[ ${#tail_output} -gt 500 ]]; then
        tail_output="${tail_output:0:500}..."
    fi

    echo "$tail_output"
}
