# CC CLI Auto-Recovery Monitoring System - Design Document

> Created: 2026-03-07
> Status: Approved for Implementation

---

## Overview

A file-based auto-recovery monitoring system for Claude Code CLI tasks. The system monitors task status,files, detects errors and stalls, and automatically recovers tasks within defined budgets.

**Core Principle:** File state is the Source of Truth. tmux output is only auxiliary diagnostics.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    cc-auto-recover.sh                            │
│                      (cron: */5 * * * *)                         │
├─────────────────────────────────────────────────────────────────┤
│  Layer D: Notification                                            │
│  └─ Discord webhook (only on max retries / fatal errors)         │
├─────────────────────────────────────────────────────────────────┤
│  Layer C: Recovery Actions                                        │
│  ├─ continue (for connection errors, max 3 retries)              │
│  ├─ re_dispatch (for stalled tasks)                              │
│  └─ alert (for fatal errors / max retries exceeded)              │
├─────────────────────────────────────────────────────────────────┤
│  Layer B: Heuristic Analysis                                      │
│  ├─ Time-based: queue > 5min, running > 10min no output          │
│  └─ Pattern-based: error keywords in output                      │
├─────────────────────────────────────────────────────────────────┤
│  Layer A: Source of Truth (File-based)                           │
│  ├─ Queue: claude-code-dispatch-macos/data/queue/*.json          │
│  ├─ Running: claude-code-dispatch-macos/data/running/*.json      │
│  └─ Output: task-output.txt, task-exit-code.txt, meta.json       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Section 1: Task State Machine

### 1.1 States (13)

| State               | Description                                                     |
| ------------------- | --------------------------------------------------------------- |
| `queued`            | Queue file exists, no owner                                     |
| `claimed`           | Has owner + claimed_at, but no execution evidence               |
| `running`           | Has started_at + run_id + execution artifact                    |
| `soft_stalled`      | running > 10min + no output change + no high-value state change |
| `hard_stalled`      | running > 20min + no execution activity signal                  |
| `recoverable_error` | Hit recoverable error pattern                                   |
| `recovering`        | Executing recovery action                                       |
| `retry_exhausted`   | Recovery budget exhausted                                       |
| `failed`            | Unrecoverable or manually marked failed                         |
| `done`              | Normal completion                                               |
| `worker_dead`       | queue > 5min unclaimed                                          |
| `expired`           | Timeout unprocessed                                             |
| `suppressed`        | Suppressed by system due to duplicate                           |

### 1.2 State Definitions

**claimed vs running boundary:**

- `claimed`: owner + claimed_at (no execution evidence yet)
- `running`: started_at + run_id + execution artifact (output file created/growing)

**recoverable_error vs hard_stalled:**

- `recoverable_error`: Based on error pattern → enter recovery
- `hard_stalled`: Based on activity absence → enter recovery judgment

---

## Section 2: Recovery Budget

### 2.1 Budget Rules

| Action        | Budget                                      | Cooldown | Prerequisites                                                                                     |
| ------------- | ------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `continue`    | 3 times/run                                 | 120s     | ① Hit recoverable pattern ② Current run owns lease ③ No duplicate active run                      |
| `re_dispatch` | 1 time/task (auto budget)                   | 300s     | ① hard_stalled or worker_dead ② Safe to reentrant ③ No duplicate active run ④ Within retry budget |
| `alert`       | Unlimited (same task+reason cooldown 15min) | -        | ① retry_exhausted ② fatal_pattern ③ dangerous_duplicate                                           |

### 2.2 Budget Granularity

- **continue**: Counted per `run_id` (not file path)
- **re_dispatch**: Counted per `task_name` (not run_id, since re_dispatch creates new run_id)
- **alert**: Cooldown per `task_name + reason` pair

---

## Section 3: Lease Mechanism

### 3.1 Lease Structure

```json
{
  "lease": {
    "owner": "cc-auto-recover@hostname#pid1234",
    "lease_id": "lease-1771684940-abc123",
    "acquired_at": 1771684940,
    "expires_at": 1771685540
  }
}
```

### 3.2 Lease Rules

- **TTL**: 10 minutes (cron 5min → lease 10min to avoid boundary conflicts)
- **Owner format**: `script_name@hostname#pid`
- **Acquisition**: Must perform "write-then-verify" atomic operation
- **Renewal**: Auto-renew when execution time exceeds half TTL (5 minutes)
- **Cleanup**: Clear on normal completion; rely on TTL for crash recovery
- **Validation**: Must verify lease ownership before and after any action

### 3.3 Lease Acquisition Flow

```bash
acquire_lease() {
  # 1. Generate lease_id
  lease_id="lease-$(date +%s)-$(random_string 6)"

  # 2. Check existing lease
  if has_valid_lease "$meta"; then
    return "LEASE_EXISTS"
  fi

  # 3. Atomic write (use mv for atomicity)
  new_meta=$(echo "$meta" | jq --arg lease_id "$lease_id" \
    --arg owner "$OWNER" \
    --argjson now "$(date +%s)" \
    --argjson expires "$(($(date +%s) + 600))" \
    '.lease = {owner: $owner, lease_id: $lease_id, acquired_at: $now, expires_at: $expires}')

  echo "$new_meta" > "$run_dir/meta.json.tmp"
  mv "$run_dir/meta.json.tmp" "$run_dir/meta.json"

  # 4. Write-then-verify
  verify_meta=$(cat "$run_dir/meta.json")
  verify_lease_id=$(echo "$verify_meta" | jq -r '.lease.lease_id')

  if [ "$verify_lease_id" != "$lease_id" ]; then
    return "LEASE_CONFLICT"
  fi

  return "LEASE_ACQUIRED"
}
```

---

## Section 4: Stall Detection

### 4.1 Soft Stall vs Hard Stall

| Type           | Condition                                                       | Action                        |
| -------------- | --------------------------------------------------------------- | ----------------------------- |
| **soft_stall** | running > 10min + no output change + no high-value state change | Log only + count, no recovery |
| **hard_stall** | running > 20min + no execution activity signal                  | Enter recovery judgment       |

### 4.2 Execution Activity Signals

**Any one satisfied means NOT hard_stall:**

1. Associated process still exists
2. task-output.txt mtime/size changed
3. meta.json status update time changed
4. Hook events for this run updated
5. exit code file appeared

### 4.3 High-Value Files (Priority Check)

1. task-output.txt (mtime + size)
2. task-exit-code.txt (exists?)
3. meta.json (status update time)
4. Supplemental: other files in run_dir (last resort)

### 4.4 Hard Stall Recovery Flow

```
hard_stalled
  ├─► If continue applicable → continue
  ├─► If not continue + safe reentrant → re_dispatch
  └─► If neither → alert + failed
```

### 4.5 Soft Stall Tracking

```json
{
  "soft_stall": {
    "count": 3,
    "first_at": 1771684940,
    "last_at": 1771685120
  }
}
```

**Note:** Track at run granularity, not task granularity.

---

## Section 5: Safe Reentrant Determination

### 5.1 Classification

| Type                      | Judgment Logic                      | Auto Recovery |
| ------------------------- | ----------------------------------- | ------------- |
| **A. Default Safe**       | All A conditions met                | ✅ Allow      |
| **B. Conditional**        | All B conditions met + extra checks | ⚠️ Careful    |
| **C. Not Auto-Reentrant** | Any C condition hit                 | ❌ Prohibit   |

### 5.2 Class A: Default Safe Reentrant

**Must meet ALL (not "any"):**

- [ ] Pure analysis/research/report task
- [ ] **Explicitly no repo write operations**
- [ ] Output is independent result file (overwritable or versionable)
- [ ] No external side effects (no API calls, no notifications, no external writes)

**⚠️ Important:** "Independent worktree" is NOT a Class A condition! Independent worktree can still have push/PR/external effects.

### 5.3 Class B: Conditional Reentrant

**Must meet ALL:**

- [ ] **Independent worktree** (not shared)
- [ ] Not yet pushed / no PR opened
- [ ] No external side effects
- [ ] Marked `reentrant=true` OR passed extra checks

**Extra checks (must pass):**

```bash
# Check unpushed changes
git -C "$worktree" diff origin/main...HEAD --quiet || exit 1

# Check PR exists
pr_num=$(gh pr list --head "$branch" --json number -q '.[0].number')
[ -z "$pr_num" ] || exit 1
```

### 5.4 Class C: Not Auto-Reentrant

**Any one means prohibited:**

- [x] Shared worktree
- [x] May push to same branch
- [x] Already triggered external side effects
- [x] Continuation-type session task (relies on historical context)
- [x] Marked `reentrant=false`

**Handling:**

```
Class C task hits hard_stall
  └─► No re_dispatch
      └─► Try continue (if applicable)
          └─► If continue fails → alert + failed
```

---

## Section 6: Duplicate Detection

### 6.1 Classification

| Type             | Condition                                                                              | Risk   | Action         |
| ---------------- | -------------------------------------------------------------------------------------- | ------ | -------------- |
| **benign**       | Old run suppressed, no concurrent write risk                                           | Low    | Log only       |
| **suppressible** | Duplicate queued/claim/recovery rescan, can determine unique valid run via lease/owner | Medium | Suppress + log |
| **dangerous**    | Two valid active owners, two running writers, lease conflict unresolvable              | High   | Alert          |

### 6.2 Detection Rules

Must combine with lease + status, not just task_name count:

- Same task_name with multiple queued
- Same task_name with multiple running
- Old run recovering + new run started
- Same owner duplicate claim
- Different owner conflict

### 6.3 Suppress Rules

**Who to suppress:**

- Among same task_name, the run with **earlier start_time**
- If same time, smaller run_id by dictionary order

---

## Section 7: Error Patterns

### 7.1 Recoverable Patterns (Auto Continue)

| Pattern             | Condition          | Action   |
| ------------------- | ------------------ | -------- |
| `unable to connect` | Network error      | continue |
| `API unconnected`   | API error          | continue |
| `ECONNREFUSED`      | Connection refused | continue |
| `ETIMEDOUT`         | Timeout            | continue |
| `network error`     | Network issue      | continue |
| `session expired`   | Session timeout    | continue |

### 7.2 Fatal Patterns (Direct Alert)

| Pattern                    | Reason                             | Action |
| -------------------------- | ---------------------------------- | ------ |
| `fatal_pattern`            | Fatal error (syntax, missing deps) | alert  |
| `auth_failure`             | Auth failed                        | alert  |
| `quota_exhausted`          | Recovery budget exhausted          | alert  |
| `dangerous_duplicate`      | Duplicate conflict                 | alert  |
| `worker_dead_long`         | Worker dead too long               | alert  |
| `hard_stall_unrecoverable` | Hard stall not recoverable         | alert  |

---

## Section 8: Notification

### 8.1 Alert Reasons (Standardized Enum)

| Reason                     | Trigger                             | Cooldown |
| -------------------------- | ----------------------------------- | -------- |
| `fatal_pattern`            | Hit fatal error pattern             | 15 min   |
| `retry_exhausted`          | Recovery budget exhausted           | 15 min   |
| `dangerous_duplicate`      | Two active owners / running writers | 15 min   |
| `worker_dead`              | queue > 5min unclaimed              | 15 min   |
| `hard_stall_unrecoverable` | Hard stall and not recoverable      | 15 min   |
| `auth_failure`             | Auth failed                         | 30 min   |
| `quota_exhausted`          | Quota exhausted                     | 30 min   |

### 8.2 Notification Format

```json
{
  "embeds": [
    {
      "title": "⚠️ CC CLI Alert",
      "description": "**Task:** cc-feature-auth\n**Run:** 1771684942-cc-feature-auth\n**Reason:** retry_exhausted",
      "color": 16711680,
      "fields": [
        { "name": "Status", "value": "retry_exhausted" },
        { "name": "Recovery Attempts", "value": "3/3 (continue)" }
      ]
    }
  ]
}
```

---

## Section 9: File Structure

### 9.1 Directory Layout

```
claude-code-dispatch-macos/
├── data/
│   ├── queue/
│   ├── running/
│   │   └── 1771684942-cc-feature-auth/
│   │       ├── meta.json
│   │       ├── task-output.txt
│   │       ├── task-exit-code.txt
│   │       └── recovery-log.json
│   ├── done/
│   └── latest.json
│
├── scripts/
│   ├── cc-auto-recover.sh
│   └── install-cc-monitor.sh
│
└── logs/
    └── cc-auto-recover.log
```

### 9.2 meta.json Full Structure

```json
{
  "task_name": "cc-feature-auth",
  "run_id": "1771684942-cc-feature-auth",
  "status": "running",

  "created_at": 1771684942,
  "started_at": 1771684945,
  "updated_at": 1771684950,

  "worktree": "../cc-feature-auth",
  "branch": "feat/auth",

  "task_type": "feature",
  "repo_write": true,
  "output_type": "code_change",
  "external_side_effects": false,
  "reentrant": null,

  "soft_stall": {
    "count": 3,
    "first_at": 1771685000,
    "last_at": 1771685200
  },

  "recovery": {
    "continue_attempts": 1,
    "re_dispatch_attempts": 0,
    "last_recovery_at": 1771685100,
    "last_recovery_action": "continue"
  },

  "lease": {
    "owner": "cc-auto-recover@you-macbook#pid1234",
    "lease_id": "lease-1771685100-abc123",
    "acquired_at": 1771685100,
    "expires_at": 1771685700
  }
}
```

### 9.3 Cron Configuration

```bash
# crontab -e
*/5 * * * * $HOME/.openclaw/scripts/cc-auto-recover.sh >> $HOME/.openclaw/logs/cc-auto-recover.log 2>&1
```

---

## Implementation Checklist

- [ ] Create `cc-auto-recover.sh` script
- [ ] Implement state machine transitions
- [ ] Implement lease acquisition/verification flow
- [ ] Implement soft/hard stall detection
- [ ] Implement safe reentrant determination
- [ ] Implement duplicate detection (3-tier)
- [ ] Implement error pattern matching
- [ ] Implement Discord notification
- [ ] Install cron job
- [ ] Add recovery tracking fields to meta.json
- [ ] Test with simulated error scenarios

---

## References

- Inspired by: https://x.com/elvissun/status/2025920521871716562
- Local config: `~/.openclaw/openclaw.json`
- Task naming convention: `cc-<slug>` (task_name, tmux session)
