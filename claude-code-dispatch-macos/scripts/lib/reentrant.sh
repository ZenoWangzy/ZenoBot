#!/usr/bin/env bash
# reentrant.sh - Safe reentrant determination for CC auto-recovery
# Classifies tasks by re-dispatch safety: Class A (safe), Class B (conditional), Class C (prohibited)

set -euo pipefail

# Get script directory
_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_SCRIPT_DIR}/utils.sh"
source "${_LIB_SCRIPT_DIR}/json.sh"
source "${_LIB_SCRIPT_DIR}/clock.sh"

# =============================================================================
# Classification Definitions
# =============================================================================

# Class A: Default Safe Reentrant
# Must meet ALL conditions:
# - Pure analysis/research/report task
# - Explicitly no repo write operations
# - Output is independent result file (overwritable or versionable)
# - No external side effects (no API calls, no notifications, no external writes)
is_class_a_safe() {
    local meta_file="$1"

    local task_type=$(json_get "$meta_file" '.task_type // empty')
    local repo_write=$(json_get "$meta_file" '.repo_write // true')
    local external_effects=$(json_get "$meta_file" '.external_side_effects // true')

    # 1. Task must be pure analysis/research/report
    if [[ ! "$task_type" =~ ^(analysis|research|report)$ ]]; then
        return 1
    fi

    # 2. No repo write
    if [[ "$repo_write" == "true" ]]; then
        return 1
    fi

    # 3. No external effects
    if [[ "$external_effects" == "true" ]]; then
        return 1
    fi

    return 0
}

# Class B: Conditional Reentrant
# Must meet ALL:
# - Independent worktree (not shared)
# - Not yet pushed / no PR opened
# - No external side effects
# - Marked reentrant=true OR passed extra checks
is_class_b_safe() {
    local meta_file="$1"
    local worktree=$(json_get "$meta_file" '.worktree // empty')
    local branch=$(json_get "$meta_file" '.branch // empty')

    # 1. Check explicit reentrant flag
    local reentrant=$(json_get "$meta_file" '.reentrant // null')
    if [[ "$reentrant" == "false" ]]; then
        return 1
    fi

    # 2. Check worktree independence
    if [[ -z "$worktree" ]]; then
        return 1  # No worktree = shared = not safe
    fi

    # 3. Check no external effects
    local external_effects=$(json_get "$meta_file" '.external_side_effects // true')
    if [[ "$external_effects" == "true" ]]; then
        return 1
    fi

    # 4. Check if branch has been pushed (has upstream)
    # CRITICAL: Do NOT use git diff origin/main...HEAD as proxy
    if [[ -n "$branch" ]] && [[ -d "$worktree" ]]; then
        # Check if branch has upstream (already pushed/tracked)
        local upstream
        upstream=$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)

        if [[ -n "$upstream" ]]; then
            # Upstream exists => branch already exposed externally
            return 1
        fi

        # 5. Check if PR exists
        local pr_num
        pr_num=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || true)
        if [[ -n "$pr_num" ]]; then
            return 1  # PR already exists
        fi
    fi

    return 0
}

# Class C: Not Auto-Reentrant
# Any one means prohibited:
# - Shared worktree
# - May push to same branch
# - Already triggered external side effects
# - Continuation-type session task (relies on historical context)
# - Marked reentrant=false
is_class_c() {
    local meta_file="$1"

    # 1. Check explicit reentrant=false
    local reentrant=$(json_get "$meta_file" '.reentrant // null')
    if [[ "$reentrant" == "false" ]]; then
        return 0
    fi

    # 2. Check for continuation-type session
    local session_type=$(json_get "$meta_file" '.session_type // empty')
    if [[ "$session_type" == "continuation" ]]; then
        return 0
    fi

    # 3. Check for external effects triggered
    local external_effects=$(json_get "$meta_file" '.external_side_effects // false')
    if [[ "$external_effects" == "true" ]]; then
        return 0
    fi

    # 4. Check shared worktree
    local worktree=$(json_get "$meta_file" '.worktree // empty')
    local worktree_shared=$(json_get "$meta_file" '.worktree_shared // false')
    if [[ "$worktree_shared" == "true" ]]; then
        return 0
    fi

    return 1  # Not class C
}

# =============================================================================
# Main API
# =============================================================================

# Determine if task is safe to re-dispatch
# Returns: class_a, class_b, class_c, or error
can_re_dispatch() {
    local meta_file="$1"

    # Class A = safe
    if is_class_a_safe "$meta_file"; then
        echo "class_a"
        return 0
    fi

    # Class B = conditional
    if is_class_b_safe "$meta_file"; then
        echo "class_b"
        return 0
    fi

    # Class C = not safe
    if is_class_c "$meta_file"; then
        echo "class_c"
        return 1
    fi

    echo "class_c"
    return 1
}

# Get re-dispatch recommendation
# Returns: safe, careful, prohibited
get_redispatch_recommendation() {
    local meta_file="$1"
    local classification
    classification=$(can_re_dispatch "$meta_file")

    case "$classification" in
        class_a) echo "safe - pure analysis task, no repo writes" ;;
        class_b) echo "careful - independent worktree, not yet pushed" ;;
        class_c) echo "prohibited - not safe for re-dispatch" ;;
        *) echo "unknown" ;;
    esac
}

# Check if task can safely continue (tmux)
can_continue() {
    local meta_file="$1"
    local tmux_session=$(json_get "$meta_file" '.tmux_session // empty')

    # If no tmux session, continue is not possible
    if [[ -z "$tmux_session" ]]; then
        return 1
    fi

    # Check if tmux session exists
    if tmux has-session -t "$tmux_session" 2>/dev/null; then
        return 0
    fi

    return 1
}
