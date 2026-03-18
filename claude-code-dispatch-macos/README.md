# CC Auto-Recovery Monitoring System

Automated monitoring and recovery system for Claude Code CLI tasks.

## Overview

This system monitors running CC tasks, detects stalls and errors, and automatically recovers within defined budgets using:

- **File-based state machine** with 13 states
- **Lease-based concurrency** for safe multi-process operation
- **Discord notifications** for alerts and status updates
- **Budget tracking** to prevent infinite recovery loops

## Quick Start

```bash
# Install the monitor
./scripts/install-cc-monitor.sh

# Run manually (foreground)
./scripts/cc-auto-recover.sh

# Run with custom settings
DATA_DIR=/path/to/data MONITOR_INTERVAL=30 ./scripts/cc-auto-recover.sh

# Dry run mode
./scripts/cc-auto-recover.sh --dry-run
```

## Architecture

### State Machine

```
                    ┌─────────┐
                    │ queued  │
                    └────┬────┘
                         │ claim
                    ┌────▼────┐
         ┌──────────┤ running │──────────┐
         │          └────┬────┘          │
         │               │               │
    soft_stall      error detected  hard_stall
         │               │               │
    ┌────▼────┐    ┌─────▼─────┐    ┌────▼────┐
    │soft_    │    │recoverable│    │hard_    │
    │stalled  │    │_error     │    │stalled  │
    └────┬────┘    └─────┬─────┘    └────┬────┘
         │               │               │
         └───────┬───────┴───────┬───────┘
                 │               │
            continue        re_dispatch
                 │               │
           ┌─────▼─────┐   ┌─────▼─────┐
           │recovering │   │  queued   │
           └─────┬─────┘   └───────────┘
                 │
            ┌────┴────┐
            │ done    │
            │ failed  │
            │ retry_  │
            │ exhausted│
            └─────────┘
```

### States

| State               | Description                                |
| ------------------- | ------------------------------------------ |
| `queued`            | Task in queue, waiting for worker          |
| `claimed`           | Worker claimed task, starting              |
| `running`           | Task actively running                      |
| `soft_stalled`      | No output for 10 min, recoverable          |
| `hard_stalled`      | No activity for 20 min, needs intervention |
| `recoverable_error` | Transient error detected                   |
| `recovering`        | Recovery action in progress                |
| `retry_exhausted`   | Recovery budget exhausted                  |
| `failed`            | Fatal error or unrecoverable               |
| `done`              | Task completed successfully                |
| `worker_dead`       | Queue item unclaimed > 5 min               |
| `expired`           | Task exceeded max runtime                  |
| `suppressed`        | Duplicate task suppressed                  |

### Detection Thresholds

| Type          | Threshold          | Action                         |
| ------------- | ------------------ | ------------------------------ |
| Soft stall    | 10 min no output   | Try continue, then re_dispatch |
| Hard stall    | 20 min no activity | Alert + re_dispatch if safe    |
| Worker dead   | 5 min unclaimed    | Alert                          |
| Queue timeout | 5 min in queue     | Alert                          |

## Recovery Actions

### 1. Continue (tmux)

Send "continue" command to tmux session:

- Max **3 attempts per run**
- 5 min cooldown between attempts
- Only for recoverable errors and soft stalls

### 2. Re-dispatch

Create new queue entry with original prompt:

- Max **1 attempt per task_name**
- Only for Class A (safe) or Class B (conditional) tasks
- Class C tasks are not re-dispatched

### 3. Alert

Send Discord notification:

- Fatal errors (immediate)
- Hard stalls (immediate)
- Budget exhaustion (immediate)
- Recovery attempts (info)

## Reentrant Safety Classification

### Class A - Safe (Default)

Pure analysis/research/report tasks:

- No repo write operations
- No external side effects
- Output is independent result file

### Class B - Conditional

Development tasks with isolation:

- Independent worktree (not shared)
- Not yet pushed / no PR opened
- No external side effects

### Class C - Prohibited

Not safe for re-dispatch:

- Shared worktree
- May push to same branch
- Already triggered external effects
- Continuation-type session

## Duplicate Detection

### Three-Tier Classification

| Type         | Condition              | Action         |
| ------------ | ---------------------- | -------------- |
| Benign       | Multiple queued/done   | Just log       |
| Suppressible | 2 running, 1 has lease | Suppress older |
| Dangerous    | 2+ with valid lease    | Alert only     |

### Suppression Precedence

1. Valid lease holder wins
2. Active writer wins (recent output)
3. Run ID tiebreaker

## File Structure

```
data/
├── queue/              # Pending tasks
│   └── task-*.json     # Queue entries
├── running/            # Active runs
│   └── run-*/
│       ├── meta.json           # Run metadata
│       ├── task-output.txt     # Task output
│       └── task-exit-code.txt  # Exit code (when done)
├── done/               # Completed runs
└── .budgets/           # Budget tracking
    └── task-name.json  # Per-task redispatch count
```

### meta.json Schema

```json
{
  "task_name": "feature-x",
  "status": "running",
  "created_at": 1709817600,
  "started_at": 1709817700,
  "updated_at": 1709818300,
  "tmux_session": "cc-feature-x",
  "original_prompt": "Implement feature X...",
  "lease": {
    "holder": "monitor-123",
    "expires_at": 1709818900
  },
  "recovery": {
    "continue_count": 0,
    "last_action": null,
    "last_action_at": null
  },
  "soft_stall": {
    "count": 0,
    "first_at": null,
    "last_at": null
  }
}
```

## Configuration

### Environment Variables

| Variable                  | Default                          | Description                        |
| ------------------------- | -------------------------------- | ---------------------------------- |
| `DATA_DIR`                | `~/.openclaw/workspace/.../data` | Data directory                     |
| `MONITOR_INTERVAL`        | `60`                             | Monitoring interval (seconds)      |
| `DRY_RUN`                 | `false`                          | Dry run mode                       |
| `MAX_CONTINUE_PER_RUN`    | `3`                              | Max continue attempts per run      |
| `MAX_REDISPATCH_PER_TASK` | `1`                              | Max redispatch per task_name       |
| `RECOVERY_COOLDOWN`       | `300`                            | Cooldown between recovery attempts |
| `SOFT_STALL_THRESHOLD`    | `600`                            | Soft stall threshold (seconds)     |
| `HARD_STALL_THRESHOLD`    | `1200`                           | Hard stall threshold (seconds)     |
| `QUEUE_TIMEOUT`           | `300`                            | Queue unclaimed timeout            |
| `RETENTION_DAYS`          | `7`                              | Days to keep completed runs        |
| `LEASE_TTL`               | `600`                            | Lease TTL (seconds)                |
| `DISCORD_WEBHOOK_URL`     | -                                | Discord webhook for alerts         |

## Testing

```bash
# Run basic tests
./tests/test-basic.sh

# Test specific component
./tests/test-lease.sh
./tests/test-state.sh
./tests/test-patterns.sh
```

## Troubleshooting

### Monitor not starting

1. Check `jq` is installed: `jq --version`
2. Check directories exist: `ls -la $DATA_DIR`
3. Check permissions: `ls -la scripts/cc-auto-recover.sh`

### Tasks not being recovered

1. Check task status: `cat $DATA_DIR/running/*/meta.json | jq .status`
2. Check lease status: `cat $DATA_DIR/running/*/meta.json | jq .lease`
3. Check recovery budget: `cat $DATA_DIR/.budgets/*.json`
4. Check logs: `tail -f logs/monitor.log`

### Duplicate detection issues

1. List all runs for task: `find $DATA_DIR -name meta.json -exec grep -l "task_name" {} \;`
2. Check classification: Look for `classify_duplicate` in logs
3. Manual suppression: Update meta.json with `"status": "suppressed"`

## Related Documentation

- Design Document: `docs/plans/2026-03-07-cc-auto-recover-design.md`
- Implementation Plan: `docs/plans/2026-03-07-cc-auto-recover-impl.md`
