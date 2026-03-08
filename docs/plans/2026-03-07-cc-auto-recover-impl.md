# CC CLI Auto-Recovery Monitoring System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a file-based auto-recovery monitoring system for Claude Code CLI tasks that detects errors/stalls and automatically recovers within defined budgets.

**Architecture:** File state machine with 13 states, lease-based concurrency control, soft/hard stall detection, and Discord notifications. Uses jq for JSON manipulation, bash for scripting.

**Tech Stack:** Bash, jq, curl, git, cron, Discord webhook

---

## Task 1: Project Setup and Directory Structure

**Files:**

- Create: `claude-code-dispatch-macos/` (if not exists)
- Create: `claude-code-dispatch-macos/scripts/cc-auto-recover.sh`
- Create: `claude-code-dispatch-macos/scripts/install-cc-monitor.sh`
- Create: `claude-code-dispatch-macos/logs/.gitkeep`

**Step 1: Verify project structure exists**

```bash
ls -la claude-code-dispatch-macos/ 2>/dev/null || mkdir -p claude-code-dispatch-macos/{data/{queue,running,done},scripts,logs}
```

Expected: Directory structure created or already exists

**Step 2: Create log directory placeholder**

```bash
touch claude-code-dispatch-macos/logs/.gitkeep
```

Expected: `.gitkeep` file created

**Step 3: Commit structure**

```bash
git add claude-code-dispatch-macos/
git commit -m "chore: create cc-auto-recover directory structure"
```

---

## Task 2: Core Utility Functions

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/utils.sh`

**Step 1: Create utils.sh with logging functions**

```bash
mkdir -p claude-code-dispatch-macos/scripts/lib
cat > claude-code-dispatch-macos/scripts/lib/utils.sh << 'EOF'
#!/bin/bash
# Core utility functions for CC auto-recovery

# Configuration
LOG_FILE="${LOG_FILE:-$HOME/.openclaw/logs/cc-auto-recover.log}"
DATA_DIR="${DATA_DIR:-$HOME/claude-code-dispatch-macos/data}"
OWNER_ID="cc-auto-recover@$(hostname)#pid$$"

# Logging
log() {
  local level="$1"
  shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && log "DEBUG" "$@"; }

# Generate unique IDs
generate_lease_id() {
  echo "lease-$(date +%s)-$(head -c 6 /dev/urandom | xxd -p)"
}

generate_run_id() {
  echo "$(date +%s)-$(head -c 8 /dev/urandom | xxd -p)"
}

# JSON helpers (require jq)
json_get() {
  local file="$1"
  local path="$2"
  jq -r "$path // empty" "$file" 2>/dev/null
}

json_set() {
  local file="$1"
  shift
  local tmp="${file}.tmp"
  jq "$@" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Time helpers
now_ts() {
  date +%s
}

ts_to_iso() {
  local ts="$1"
  date -u -r "$ts" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$ts" '+%Y-%m-%dT%H:%M:%SZ'
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/utils.sh
```

Expected: `utils.sh` created with logging and helper functions

**Step 2: Verify jq is available**

```bash
which jq && jq --version
```

Expected: jq path and version (e.g., `jq-1.6`)

**Step 3: Commit utility functions**

```bash
git add claude-code-dispatch-macos/scripts/lib/utils.sh
git commit -m "feat(cc-recover): add core utility functions"
```

---

## Task 3: Lease Management Module

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/lease.sh`

**Step 1: Create lease.sh with acquisition/release functions**

```bash
cat > claude-code-dispatch-macos/scripts/lib/lease.sh << 'EOF'
#!/bin/bash
# Lease management for CC auto-recovery
# Source: scripts/lib/utils.sh must be sourced first

LEASE_TTL=${LEASE_TTL:-600}  # 10 minutes

# Check if lease is valid
lease_is_valid() {
  local meta_file="$1"
  local now=$(now_ts)

  local expires=$(json_get "$meta_file" '.lease.expires_at // 0')
  local lease_id=$(json_get "$meta_file" '.lease.lease_id // empty')

  [[ -n "$lease_id" && "$now" -lt "$expires" ]]
}

# Check if we own the lease
lease_is_owner() {
  local meta_file="$1"
  local expected_owner="$2"

  local actual_owner=$(json_get "$meta_file" '.lease.owner // empty')
  [[ "$actual_owner" == "$expected_owner" ]]
}

# Acquire lease (write-then-verify)
acquire_lease() {
  local meta_file="$1"
  local owner="$2"
  local lease_id=$(generate_lease_id)
  local now=$(now_ts)
  local expires=$((now + LEASE_TTL))

  # Check existing lease
  if lease_is_valid "$meta_file"; then
    log_debug "Valid lease already exists: $meta_file"
    return 1  # LEASE_EXISTS
  fi

  # Atomic write using mv
  local tmp="${meta_file}.tmp.$$"
  json_set "$meta_file" \
    --arg owner "$owner" \
    --arg lease_id "$lease_id" \
    --argjson now "$now" \
    --argjson expires "$expires" \
    '.lease = {owner: $owner, lease_id: $lease_id, acquired_at: $now, expires_at: $expires}'

  # Write-then-verify
  local verify_lease_id=$(json_get "$meta_file" '.lease.lease_id // empty')
  if [[ "$verify_lease_id" != "$lease_id" ]]; then
    log_warn "Lease conflict detected: expected=$lease_id, actual=$verify_lease_id"
    return 2  # LEASE_CONFLICT
  fi

  log_info "Lease acquired: $lease_id for $meta_file"
  echo "$lease_id"  # Return lease_id for tracking
  return 0
}

# Verify we still own the lease
verify_lease() {
  local meta_file="$1"
  local expected_lease_id="$2"
  local now=$(now_ts)

  local actual_lease_id=$(json_get "$meta_file" '.lease.lease_id // empty')
  local expires=$(json_get "$meta_file" '.lease.expires_at // 0')

  if [[ "$actual_lease_id" != "$expected_lease_id" ]]; then
    return 1  # Not our lease
  fi

  if [[ "$now" -ge "$expires" ]]; then
    return 2  # Lease expired
  fi

  return 0
}

# Renew lease (extend TTL)
renew_lease() {
  local meta_file="$1"
  local current_lease_id="$2"

  if ! verify_lease "$meta_file" "$current_lease_id"; then
    log_warn "Cannot renew: lease lost or expired"
    return 1
  fi

  local now=$(now_ts)
  local new_expires=$((now + LEASE_TTL))

  json_set "$meta_file" \
    --argjson expires "$new_expires" \
    '.lease.expires_at = $expires'

  # Verify renewal
  local verify_expires=$(json_get "$meta_file" '.lease.expires_at')
  if [[ "$verify_expires" != "$new_expires" ]]; then
    return 2
  fi

  log_debug "Lease renewed until $(ts_to_iso $new_expires)"
  return 0
}

# Clear lease
clear_lease() {
  local meta_file="$1"

  json_set "$meta_file" '.lease = null'
  log_debug "Lease cleared: $meta_file"
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/lease.sh
```

Expected: `lease.sh` created with lease management functions

**Step 2: Test lease functions manually**

```bash
source claude-code-dispatch-macos/scripts/lib/utils.sh
source claude-code-dispatch-macos/scripts/lib/lease.sh

# Create test meta file
echo '{"task_name":"test","status":"running"}' > /tmp/test-meta.json

# Test acquire
acquire_lease /tmp/test-meta.json "test-owner"
cat /tmp/test-meta.json | jq '.lease'

# Cleanup
rm /tmp/test-meta.json
```

Expected: Lease acquired with owner, lease_id, timestamps

**Step 3: Commit lease module**

```bash
git add claude-code-dispatch-macos/scripts/lib/lease.sh
git commit -m "feat(cc-recover): add lease management module"
```

---

## Task 4: State Detection Module

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/state.sh`

**Step 1: Create state.sh with stall detection**

```bash
cat > claude-code-dispatch-macos/scripts/lib/state.sh << 'EOF'
#!/bin/bash
# State detection for CC auto-recovery

# Thresholds (seconds)
SOFT_STALL_THRESHOLD=${SOFT_STALL_THRESHOLD:-600}   # 10 minutes
HARD_STALL_THRESHOLD=${HARD_STALL_THRESHOLD:-1200}  # 20 minutes
QUEUE_TIMEOUT=${QUEUE_TIMEOUT:-300}                  # 5 minutes

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

# Check execution activity signals
has_activity_signal() {
  local run_dir="$1"
  local meta_file="${run_dir}/meta.json"
  local now=$(now_ts)

  # Signal 1: Check recent meta.json update (within 5 min)
  local updated_at=$(json_get "$meta_file" '.updated_at // 0')
  if [[ $((now - updated_at)) -lt 300 ]]; then
    return 0
  fi

  # Signal 2: Check output file changes
  local output_file="${run_dir}/task-output.txt"
  if [[ -f "$output_file" ]]; then
    local mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null)
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

# Detect soft stall
is_soft_stalled() {
  local run_dir="$1"
  local meta_file="${run_dir}/meta.json"
  local now=$(now_ts)

  local status=$(get_status "$meta_file")
  [[ "$status" != "running" ]] && return 1

  local started_at=$(json_get "$meta_file" '.started_at // 0')
  local elapsed=$((now - started_at))

  # Check time threshold
  [[ "$elapsed" -lt "$SOFT_STALL_THRESHOLD" ]] && return 1

  # Check no output change
  local output_file="${run_dir}/task-output.txt"
  if [[ -f "$output_file" ]]; then
    local mtime=$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null)
    if [[ $((now - mtime)) -lt 300 ]]; then
      return 1  # Recent output
    fi
  fi

  return 0
}

# Detect hard stall
is_hard_stalled() {
  local run_dir="$1"
  local meta_file="${run_dir}/meta.json"
  local now=$(now_ts)

  local status=$(get_status "$meta_file")
  [[ "$status" != "running" ]] && return 1

  local started_at=$(json_get "$meta_file" '.started_at // 0')
  local elapsed=$((now - started_at))

  # Check time threshold
  [[ "$elapsed" -lt "$HARD_STALL_THRESHOLD" ]] && return 1

  # Check activity signals
  has_activity_signal "$run_dir" && return 1

  return 0
}

# Detect worker dead (queue timeout)
is_worker_dead() {
  local queue_file="$1"
  local now=$(now_ts)

  local created_at=$(json_get "$queue_file" '.created_at // 0')
  local status=$(get_status "$queue_file")

  [[ "$status" == "queued" ]] || return 1

  local elapsed=$((now - created_at))
  [[ "$elapsed" -ge "$QUEUE_TIMEOUT" ]]
}

# Record soft stall
record_soft_stall() {
  local meta_file="$1"
  local now=$(now_ts)

  local count=$(json_get "$meta_file" '.soft_stall.count // 0')
  local first=$(json_get "$meta_file" '.soft_stall.first_at // empty')

  if [[ -z "$first" ]]; then
    first="$now"
  fi

  json_set "$meta_file" \
    --argjson count $((count + 1)) \
    --argjson first "$first" \
    --argjson last "$now" \
    '.soft_stall = {count: $count, first_at: $first, last_at: $last}'
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/state.sh
```

Expected: `state.sh` created with stall detection functions

**Step 2: Commit state module**

```bash
git add claude-code-dispatch-macos/scripts/lib/state.sh
git commit -m "feat(cc-recover): add state detection module"
```

---

## Task 5: Error Pattern Detection

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/patterns.sh`

**Step 1: Create patterns.sh with error matching**

```bash
cat > claude-code-dispatch-macos/scripts/lib/patterns.sh << 'EOF'
#!/bin/bash
# Error pattern detection for CC auto-recovery

# Recoverable patterns (can auto-continue)
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
)

# Fatal patterns (direct alert)
FATAL_PATTERNS=(
  "cannot be launched inside another Claude Code session"
  "unrecognized arguments"
  "requires a valid session ID"
  "authentication failed"
  "invalid API key"
  "quota exceeded"
  "fatal error"
)

# Check if output matches recoverable pattern
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

# Detect error type
detect_error_type() {
  local output="$1"

  if is_fatal_error "$output"; then
    echo "fatal"
    return 0
  fi

  if is_recoverable_error "$output"; then
    echo "recoverable"
    return 0
  fi

  echo "unknown"
  return 1
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/patterns.sh
```

Expected: `patterns.sh` created with error pattern matching

**Step 2: Commit patterns module**

```bash
git add claude-code-dispatch-macos/scripts/lib/patterns.sh
git commit -m "feat(cc-recover): add error pattern detection"
```

---

## Task 6: Safe Reentrant Determination

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/reentrant.sh`

**Step 1: Create reentrant.sh with safety checks**

```bash
cat > claude-code-dispatch-macos/scripts/lib/reentrant.sh << 'EOF'
#!/bin/bash
# Safe reentrant determination for CC auto-recovery

# Class A: Default safe reentrant
# Must meet ALL conditions
is_class_a_safe() {
  local meta_file="$1"

  local task_type=$(json_get "$meta_file" '.task_type // empty')
  local repo_write=$(json_get "$meta_file" '.repo_write // true')
  local external_effects=$(json_get "$meta_file" '.external_side_effects // true')

  # All must be true:
  # 1. Pure analysis/research/report
  [[ ! "$task_type" =~ ^(analysis|research|report)$ ]] && return 1

  # 2. No repo write
  [[ "$repo_write" == "true" ]] && return 1

  # 3. No external effects
  [[ "$external_effects" == "true" ]] && return 1

  return 0
}

# Class B: Conditional reentrant
# Must meet ALL + extra checks
is_class_b_safe() {
  local meta_file="$1"
  local run_dir=$(dirname "$meta_file")

  # Check explicit reentrant flag
  local reentrant=$(json_get "$meta_file" '.reentrant // null')
  [[ "$reentrant" == "false" ]] && return 1

  # Check worktree independence
  local worktree=$(json_get "$meta_file" '.worktree // empty')
  if [[ -z "$worktree" ]]; then
    return 1  # No worktree = shared = not safe
  fi

  # Check if already pushed
  local branch=$(json_get "$meta_file" '.branch // empty')
  if [[ -n "$branch" ]] && [[ -d "$worktree/.git" || -f "$worktree/.git" ]]; then
    # Check unpushed changes
    if ! git -C "$worktree" diff origin/main...HEAD --quiet 2>/dev/null; then
      return 1  # Has unpushed changes
    fi

    # Check PR exists
    local pr_num=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null)
    if [[ -n "$pr_num" ]]; then
      return 1  # PR already exists
    fi
  fi

  # Check external effects
  local external_effects=$(json_get "$meta_file" '.external_side_effects // true')
  [[ "$external_effects" == "true" ]] && return 1

  return 0
}

# Determine if task is safe to re-dispatch
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
  echo "class_c"
  return 1
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/reentrant.sh
```

Expected: `reentrant.sh` created with safety determination

**Step 2: Commit reentrant module**

```bash
git add claude-code-dispatch-macos/scripts/lib/reentrant.sh
git commit -m "feat(cc-recover): add safe reentrant determination"
```

---

## Task 7: Duplicate Detection

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/duplicate.sh`

**Step 1: Create duplicate.sh with detection logic**

```bash
cat > claude-code-dispatch-macos/scripts/lib/duplicate.sh << 'EOF'
#!/bin/bash
# Duplicate detection for CC auto-recovery

# Find duplicate runs by task_name
find_duplicates() {
  local task_name="$1"
  local data_dir="$2"

  local duplicates=()

  # Check queue
  for f in "${data_dir}/queue"/*.json; do
    [[ -f "$f" ]] || continue
    local name=$(json_get "$f" '.task_name // empty')
    [[ "$name" == "$task_name" ]] && duplicates+=("$f")
  done

  # Check running
  for d in "${data_dir}/running"/*/; do
    [[ -d "$d" ]] || continue
    local meta="${d}meta.json"
    [[ -f "$meta" ]] || continue
    local name=$(json_get "$meta" '.task_name // empty')
    [[ "$name" == "$task_name" ]] && duplicates+=("$meta")
  done

  printf '%s\n' "${duplicates[@]}"
}

# Classify duplicate type
classify_duplicate() {
  local files=("$@")

  [[ ${#files[@]} -le 1 ]] && { echo "none"; return 0; }

  local active_count=0
  local valid_lease_count=0

  for f in "${files[@]}"; do
    local status=$(get_status "$f")
    if [[ "$status" =~ ^(running|recovering)$ ]]; then
      ((active_count++))
    fi

    if lease_is_valid "$f"; then
      ((valid_lease_count++))
    fi
  done

  # Multiple active with valid leases = dangerous
  if [[ "$active_count" -ge 2 && "$valid_lease_count" -ge 2 ]]; then
    echo "dangerous"
    return 0
  fi

  # Can determine unique valid run = suppressible
  if [[ "$valid_lease_count" -eq 1 || "$active_count" -eq 1 ]]; then
    echo "suppressible"
    return 0
  fi

  # Otherwise benign
  echo "benign"
}

# Suppress older run
suppress_run() {
  local meta_file="$1"
  local reason="$2"
  local now=$(now_ts)

  json_set "$meta_file" \
    --arg status "suppressed" \
    --arg reason "$reason" \
    --argjson now "$now" \
    '.status = $status | .suppressed_at = $now | .suppressed_reason = $reason'

  log_info "Suppressed run: $meta_file (reason: $reason)"
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/duplicate.sh
```

Expected: `duplicate.sh` created with duplicate detection

**Step 2: Commit duplicate module**

```bash
git add claude-code-dispatch-macos/scripts/lib/duplicate.sh
git commit -m "feat(cc-recover): add duplicate detection module"
```

---

## Task 8: Recovery Actions

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/recovery.sh`

**Step 1: Create recovery.sh with action execution**

```bash
cat > claude-code-dispatch-macos/scripts/lib/recovery.sh << 'EOF'
#!/bin/bash
# Recovery actions for CC auto-recovery

# Budget limits
MAX_CONTINUE_PER_RUN=${MAX_CONTINUE_PER_RUN:-3}
MAX_REDISPATCH_PER_TASK=${MAX_REDISPATCH_PER_TASK:-1}
CONTINUE_COOLDOWN=${CONTINUE_COOLDOWN:-120}
REDISPATCH_COOLDOWN=${REDISPATCH_COOLDOWN:-300}

# Check continue budget
has_continue_budget() {
  local meta_file="$1"
  local attempts=$(json_get "$meta_file" '.recovery.continue_attempts // 0')
  [[ "$attempts" -lt "$MAX_CONTINUE_PER_RUN" ]]
}

# Check re_dispatch budget
has_redispatch_budget() {
  local meta_file="$1"
  local attempts=$(json_get "$meta_file" '.recovery.re_dispatch_attempts // 0')
  [[ "$attempts" -lt "$MAX_REDISPATCH_PER_TASK" ]]
}

# Check cooldown
is_cooldown_active() {
  local meta_file="$1"
  local action="$2"
  local cooldown="$3"
  local now=$(now_ts)

  local last_recovery=$(json_get "$meta_file" '.recovery.last_recovery_at // 0')
  local elapsed=$((now - last_recovery))

  [[ "$elapsed" -lt "$cooldown" ]]
}

# Execute continue action
execute_continue() {
  local run_dir="$1"
  local meta_file="${run_dir}/meta.json"
  local tmux_session=$(json_get "$meta_file" '.tmux_session // empty')

  if [[ -z "$tmux_session" ]]; then
    log_error "No tmux session for continue: $run_dir"
    return 1
  fi

  if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
    log_warn "Tmux session not found: $tmux_session"
    return 1
  fi

  # Send continue
  tmux send-keys -t "$tmux_session" "continue" Enter

  # Update recovery tracking
  local attempts=$(json_get "$meta_file" '.recovery.continue_attempts // 0')
  json_set "$meta_file" \
    --argjson attempts $((attempts + 1)) \
    --argjson now "$(now_ts)" \
    '.recovery.continue_attempts = $attempts | .recovery.last_recovery_at = $now | .recovery.last_recovery_action = "continue"'

  log_info "Executed continue on $tmux_session (attempt $((attempts + 1))/$MAX_CONTINUE_PER_RUN)"
  return 0
}

# Execute re_dispatch action
execute_redispatch() {
  local meta_file="$1"
  local run_dir=$(dirname "$meta_file")

  local task_name=$(json_get "$meta_file" '.task_name')
  local worktree=$(json_get "$meta_file" '.worktree')
  local branch=$(json_get "$meta_file" '.branch')
  local original_prompt=$(json_get "$meta_file" '.original_prompt // empty')

  if [[ -z "$worktree" || -z "$branch" ]]; then
    log_error "Missing worktree or branch for re_dispatch"
    return 1
  fi

  # Mark current run as superseded
  json_set "$meta_file" \
    --argjson now "$(now_ts)" \
    '.status = "superseded" | .superseded_at = $now'

  # Create new dispatch (simplified - actual implementation would use dispatch system)
  log_info "Re-dispatching task: $task_name to $worktree"

  # Update recovery tracking on original task
  local attempts=$(json_get "$meta_file" '.recovery.re_dispatch_attempts // 0')
  json_set "$meta_file" \
    --argjson attempts $((attempts + 1)) \
    --argjson now "$(now_ts)" \
    '.recovery.re_dispatch_attempts = $attempts | .recovery.last_recovery_at = $now | .recovery.last_recovery_action = "re_dispatch"'

  return 0
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/recovery.sh
```

Expected: `recovery.sh` created with recovery actions

**Step 2: Commit recovery module**

```bash
git add claude-code-dispatch-macos/scripts/lib/recovery.sh
git commit -m "feat(cc-recover): add recovery actions module"
```

---

## Task 9: Notification Module

**Files:**

- Create: `claude-code-dispatch-macos/scripts/lib/notify.sh`

**Step 1: Create notify.sh with Discord integration**

```bash
cat > claude-code-dispatch-macos/scripts/lib/notify.sh << 'EOF'
#!/bin/bash
# Notification module for CC auto-recovery

# Discord webhook (from environment or config)
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

# Alert cooldown tracking
ALERT_COOLDOWN_DIR="${ALERT_COOLDOWN_DIR:-/tmp/cc-alert-cooldown}"
ALERT_COOLDOWN_DEFAULT=${ALERT_COOLDOWN_DEFAULT:-900}  # 15 minutes

# Standard alert reasons
declare -A ALERT_COOLDOWNS=(
  ["fatal_pattern"]=900
  ["retry_exhausted"]=900
  ["dangerous_duplicate"]=900
  ["worker_dead"]=900
  ["hard_stall_unrecoverable"]=900
  ["auth_failure"]=1800
  ["quota_exhausted"]=1800
)

# Check if alert is in cooldown
is_alert_in_cooldown() {
  local task_name="$1"
  local reason="$2"
  local cooldown_file="${ALERT_COOLDOWN_DIR}/${task_name}:${reason}"
  local cooldown="${ALERT_COOLDOWNS[$reason]:-$ALERT_COOLDOWN_DEFAULT}"

  mkdir -p "$ALERT_COOLDOWN_DIR"

  if [[ -f "$cooldown_file" ]]; then
    local last_alert=$(cat "$cooldown_file")
    local now=$(now_ts)
    local elapsed=$((now - last_alert))

    if [[ "$elapsed" -lt "$cooldown" ]]; then
      return 0  # In cooldown
    fi
  fi

  return 1  # Not in cooldown
}

# Record alert time
record_alert() {
  local task_name="$1"
  local reason="$2"
  local cooldown_file="${ALERT_COOLDOWN_DIR}/${task_name}:${reason}"

  echo "$(now_ts)" > "$cooldown_file"
}

# Send Discord alert
send_discord_alert() {
  local task_name="$1"
  local run_id="$2"
  local reason="$3"
  local details="$4"

  [[ -z "$DISCORD_WEBHOOK" ]] && { log_warn "No Discord webhook configured"; return 1; }

  # Check cooldown
  if is_alert_in_cooldown "$task_name" "$reason"; then
    log_debug "Alert in cooldown: $task_name:$reason"
    return 0
  fi

  local color=16711680  # Red
  local title="⚠️ CC CLI Alert"

  local payload=$(cat <<EOF
{
  "embeds": [{
    "title": "$title",
    "description": "**Task:** $task_name\n**Run:** $run_id\n**Reason:** $reason\n$details",
    "color": $color,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)

  if curl -s -X POST "$DISCORD_WEBHOOK" \
       -H "Content-Type: application/json" \
       -d "$payload" > /dev/null 2>&1; then
    record_alert "$task_name" "$reason"
    log_info "Discord alert sent: $task_name - $reason"
    return 0
  else
    log_error "Failed to send Discord alert"
    return 1
  fi
}

# Send recovery notification (optional)
send_recovery_notification() {
  local task_name="$1"
  local action="$2"
  local attempt="$3"

  [[ -z "$DISCORD_WEBHOOK" ]] && return 0

  local content="🔄 Auto-recovery: $task_name\nAction: $action (attempt $attempt)"

  curl -s -X POST "$DISCORD_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"$content\"}" > /dev/null 2>&1
}
EOF
chmod +x claude-code-dispatch-macos/scripts/lib/notify.sh
```

Expected: `notify.sh` created with Discord integration

**Step 2: Commit notification module**

```bash
git add claude-code-dispatch-macos/scripts/lib/notify.sh
git commit -m "feat(cc-recover): add notification module"
```

---

## Task 10: Main Monitor Script

**Files:**

- Create: `claude-code-dispatch-macos/scripts/cc-auto-recover.sh`

**Step 1: Create main monitor script**

```bash
cat > claude-code-dispatch-macos/scripts/cc-auto-recover.sh << 'EOF'
#!/bin/bash
# CC CLI Auto-Recovery Monitor
# Main monitoring script

set -e

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/lease.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/lib/patterns.sh"
source "${SCRIPT_DIR}/lib/reentrant.sh"
source "${SCRIPT_DIR}/lib/duplicate.sh"
source "${SCRIPT_DIR}/lib/recovery.sh"
source "${SCRIPT_DIR}/lib/notify.sh"

# Configuration
DATA_DIR="${DATA_DIR:-$HOME/claude-code-dispatch-macos/data}"
LOG_FILE="${LOG_FILE:-$HOME/.openclaw/logs/cc-auto-recover.log}"

log_info "===== CC Auto-Recover Monitor Started ====="

# Process queue tasks
process_queue() {
  log_debug "Processing queue..."

  for queue_file in "${DATA_DIR}/queue"/*.json; do
    [[ -f "$queue_file" ]] || continue

    local task_name=$(json_get "$queue_file" '.task_name // empty')
    log_debug "Checking queued task: $task_name"

    # Check for worker dead
    if is_worker_dead "$queue_file"; then
      log_warn "Worker dead detected: $task_name"
      send_discord_alert "$task_name" "pending" "worker_dead" "Queue timeout: no worker claimed task"
    fi
  done
}

# Process running tasks
process_running() {
  log_debug "Processing running tasks..."

  for run_dir in "${DATA_DIR}/running"/*/; do
    [[ -d "$run_dir" ]] || continue

    local meta_file="${run_dir}meta.json"
    [[ -f "$meta_file" ]] || continue

    local task_name=$(json_get "$meta_file" '.task_name // empty')
    local run_id=$(json_get "$meta_file" '.run_id // empty')
    local status=$(get_status "$meta_file")

    log_debug "Checking running task: $task_name ($status)"

    # Skip non-active statuses
    is_active_status "$status" || continue

    # Check for duplicate
    local duplicates=$(find_duplicates "$task_name" "$DATA_DIR")
    local dup_count=$(echo "$duplicates" | grep -c . || echo 0)
    if [[ "$dup_count" -gt 1 ]]; then
      local dup_type=$(classify_duplicate $duplicates)
      log_warn "Duplicate detected ($dup_type): $task_name"

      if [[ "$dup_type" == "dangerous" ]]; then
        send_discord_alert "$task_name" "$run_id" "dangerous_duplicate" "Multiple active runs detected"
        continue
      fi
    fi

    # Check for errors in output
    local output_file="${run_dir}task-output.txt"
    if [[ -f "$output_file" ]]; then
      local output=$(tail -100 "$output_file" 2>/dev/null || echo "")
      local error_type=$(detect_error_type "$output")

      if [[ "$error_type" == "fatal" ]]; then
        local pattern=$(is_fatal_error "$output")
        send_discord_alert "$task_name" "$run_id" "fatal_pattern" "Pattern: $pattern"
        continue
      fi

      if [[ "$error_type" == "recoverable" ]]; then
        # Try to acquire lease
        local lease_id=$(acquire_lease "$meta_file" "$OWNER_ID")
        if [[ $? -eq 0 ]]; then
          # Check continue budget
          if has_continue_budget "$meta_file" && ! is_cooldown_active "$meta_file" "continue" "$CONTINUE_COOLDOWN"; then
            execute_continue "$run_dir"
            clear_lease "$meta_file"
            continue
          else
            send_discord_alert "$task_name" "$run_id" "retry_exhausted" "Continue budget exhausted"
            clear_lease "$meta_file"
            continue
          fi
        fi
      fi
    fi

    # Check for soft stall
    if is_soft_stalled "$run_dir"; then
      log_info "Soft stall detected: $task_name"
      record_soft_stall "$meta_file"
      continue
    fi

    # Check for hard stall
    if is_hard_stalled "$run_dir"; then
      log_warn "Hard stall detected: $task_name"

      # Try to acquire lease
      local lease_id=$(acquire_lease "$meta_file" "$OWNER_ID")
      if [[ $? -eq 0 ]]; then
        # Check if safe to re_dispatch
        local safety=$(can_re_dispatch "$meta_file")

        if [[ "$safety" != "class_c" ]] && has_redispatch_budget "$meta_file" && ! is_cooldown_active "$meta_file" "re_dispatch" "$REDISPATCH_COOLDOWN"; then
          execute_redispatch "$meta_file"
        else
          send_discord_alert "$task_name" "$run_id" "hard_stall_unrecoverable" "Cannot safely re-dispatch (safety: $safety)"
        fi

        clear_lease "$meta_file"
      fi
    fi
  done
}

# Main execution
main() {
  process_queue
  process_running
  log_info "===== CC Auto-Recover Monitor Completed ====="
}

main "$@"
EOF
chmod +x claude-code-dispatch-macos/scripts/cc-auto-recover.sh
```

Expected: Main monitor script created

**Step 2: Commit main script**

```bash
git add claude-code-dispatch-macos/scripts/cc-auto-recover.sh
git commit -m "feat(cc-recover): add main monitoring script"
```

---

## Task 11: Installation Script

**Files:**

- Create: `claude-code-dispatch-macos/scripts/install-cc-monitor.sh`

**Step 1: Create installation script**

```bash
cat > claude-code-dispatch-macos/scripts/install-cc-monitor.sh << 'EOF'
#!/bin/bash
# Installation script for CC Auto-Recovery Monitor

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="${SCRIPT_DIR}/cc-auto-recover.sh"
CRON_JOB="*/5 * * * * ${MONITOR_SCRIPT} >> $HOME/.openclaw/logs/cc-auto-recover.log 2>&1"

echo "=== CC Auto-Recovery Monitor Installation ==="

# Check dependencies
echo "Checking dependencies..."
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required"; exit 1; }
echo "✓ Dependencies OK"

# Create log directory
mkdir -p "$HOME/.openclaw/logs"
echo "✓ Log directory created"

# Check if cron job exists
if crontab -l 2>/dev/null | grep -q "cc-auto-recover.sh"; then
  echo "✓ Cron job already exists"
else
  # Add cron job
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  echo "✓ Cron job installed (every 5 minutes)"
fi

# Show current cron
echo ""
echo "Current cron jobs:"
crontab -l 2>/dev/null | grep -E "(cc-auto-recover)" || echo "  (none)"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Configuration:"
echo "  Monitor script: ${MONITOR_SCRIPT}"
echo "  Log file: $HOME/.openclaw/logs/cc-auto-recover.log"
echo "  Data directory: $HOME/claude-code-dispatch-macos/data"
echo ""
echo "To manually run: ${MONITOR_SCRIPT}"
echo "To view logs: tail -f $HOME/.openclaw/logs/cc-auto-recover.log"
echo ""
echo "Required environment variables:"
echo "  DISCORD_WEBHOOK - Discord webhook URL for alerts"
EOF
chmod +x claude-code-dispatch-macos/scripts/install-cc-monitor.sh
```

Expected: Installation script created

**Step 2: Commit installation script**

```bash
git add claude-code-dispatch-macos/scripts/install-cc-monitor.sh
git commit -m "feat(cc-recover): add installation script"
```

---

## Task 12: Testing

**Files:**

- Create: `claude-code-dispatch-macos/tests/test-basic.sh`

**Step 1: Create basic test script**

```bash
mkdir -p claude-code-dispatch-macos/tests
cat > claude-code-dispatch-macos/tests/test-basic.sh << 'EOF'
#!/bin/bash
# Basic tests for CC Auto-Recovery

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../scripts/lib"

source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/lease.sh"

TEST_DIR="/tmp/cc-recover-test-$$"
mkdir -p "$TEST_DIR"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "=== Running Basic Tests ==="

# Test 1: Utils
echo "Test 1: Utility functions..."
[[ $(now_ts) -gt 1700000000 ]] && echo "  ✓ now_ts works"
[[ -n "$(generate_lease_id)" ]] && echo "  ✓ generate_lease_id works"
[[ -n "$(generate_run_id)" ]] && echo "  ✓ generate_run_id works"

# Test 2: Lease
echo "Test 2: Lease functions..."
TEST_META="${TEST_DIR}/meta.json"
echo '{"task_name":"test","status":"running"}' > "$TEST_META"

LEASE_ID=$(acquire_lease "$TEST_META" "test-owner")
if [[ $? -eq 0 && -n "$LEASE_ID" ]]; then
  echo "  ✓ acquire_lease works"

  if verify_lease "$TEST_META" "$LEASE_ID"; then
    echo "  ✓ verify_lease works"
  else
    echo "  ✗ verify_lease failed"
    exit 1
  fi
else
  echo "  ✗ acquire_lease failed"
  exit 1
fi

# Test 3: JSON helpers
echo "Test 3: JSON helpers..."
VALUE=$(json_get "$TEST_META" '.task_name')
if [[ "$VALUE" == "test" ]]; then
  echo "  ✓ json_get works"
else
  echo "  ✗ json_get failed"
  exit 1
fi

echo ""
echo "=== All Tests Passed ==="
EOF
chmod +x claude-code-dispatch-macos/tests/test-basic.sh
```

Expected: Test script created

**Step 2: Run tests**

```bash
./claude-code-dispatch-macos/tests/test-basic.sh
```

Expected: All tests pass

**Step 3: Commit tests**

```bash
git add claude-code-dispatch-macos/tests/
git commit -m "test(cc-recover): add basic test suite"
```

---

## Task 13: Documentation

**Files:**

- Create: `claude-code-dispatch-macos/README.md`

**Step 1: Create README**

````bash
cat > claude-code-dispatch-macos/README.md << 'EOF'
# CC CLI Auto-Recovery Monitoring System

Automatically monitors and recovers Claude Code CLI tasks.

## Features

- **File-based state machine**: 13 states with clear transitions
- **Automatic recovery**: continue (3/run) and re_dispatch (1/task)
- **Lease mechanism**: Prevents concurrent recovery conflicts
- **Soft/hard stall detection**: Distinguishes temporary pauses from dead tasks
- **Safe reentrant determination**: Classifies tasks by re-dispatch safety
- **Discord notifications**: Alerts for critical issues

## Installation

```bash
cd claude-code-dispatch-macos
./scripts/install-cc-monitor.sh
````

## Configuration

Set environment variables:

```bash
export DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
export DATA_DIR="$HOME/claude-code-dispatch-macos/data"
```

## Directory Structure

```
claude-code-dispatch-macos/
├── data/
│   ├── queue/     # Pending tasks
│   ├── running/   # Active runs
│   └── done/      # Completed runs
├── scripts/
│   ├── cc-auto-recover.sh      # Main monitor
│   ├── install-cc-monitor.sh   # Installer
│   └── lib/                    # Module libraries
└── logs/
    └── cc-auto-recover.log
```

## Monitoring

- **Frequency**: Every 5 minutes (cron)
- **Log**: `~/.openclaw/logs/cc-auto-recover.log`
- **Manual run**: `./scripts/cc-auto-recover.sh`

## Recovery Budget

| Action      | Budget | Cooldown |
| ----------- | ------ | -------- |
| continue    | 3/run  | 120s     |
| re_dispatch | 1/task | 300s     |

## Alert Reasons

- `fatal_pattern`: Unrecoverable error
- `retry_exhausted`: Recovery budget exhausted
- `dangerous_duplicate`: Concurrent run conflict
- `worker_dead`: No worker claimed task
- `hard_stall_unrecoverable`: Stall with no safe recovery

## Design Document

See: `docs/plans/2026-03-07-cc-auto-recover-design.md`
EOF

````

Expected: README created

**Step 2: Commit README**

```bash
git add claude-code-dispatch-macos/README.md
git commit -m "docs(cc-recover): add README"
````

---

## Execution Handoff

**Plan complete and saved to `docs/plans/2026-03-07-cc-auto-recover-impl.md`.**

**Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
