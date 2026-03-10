# CC Dispatch Notification Reliability Fix Design

**Date**: 2026-03-05
**Status**: Approved (mode=auto)
**Approach**: Minimal fixes (Option A)

## Problem Statement

Five reliability issues in CC dispatch notification system:

1. **Task-meta status not finalized**: Hook may read stale status before worker updates
2. **Discord notification marked delivered on failure**: `|| true` swallows errors, dedupe key written before send
3. **Notification routing unreliable**: Hook only reads task-meta.json, not latest.json
4. **No notification logging**: All output redirected to /dev/null
5. **Recovery retry only once**: Worker only does 1 retry for "unable to connect" errors

## Solution Design

### Fix 1: Task-meta Status Finalization

**File**: `worker-claude-queue.sh`
**Location**: Lines 186-197

**Change**:

- Ensure META_FILE is written and synced BEFORE triggering notification
- Worker triggers notification AFTER all status files are finalized

### Fix 2: Discord Notification Success Check

**File**: `notify-openclaw-dispatch.sh`
**Location**: Lines 129-142

**Change**:

- Write dedupe key ONLY after successful send
- Capture and log send result
- Remove `|| true` to detect failures

### Fix 3: Notification Routing Reliability

**File**: `notify-openclaw-dispatch.sh`
**Location**: Lines 64-78

**Change**:

- Read callback from both `latest.json` (worker-authored) and `task-meta.json`
- Prefer `latest.json` as it contains complete run information
- Fallback chain: latest.json → task-meta.json → DEFAULT_CALLBACK_TARGET

### Fix 4: Notification Logging

**File**: `notify-openclaw-dispatch.sh`
**Location**: Lines 136-142

**Change**:

- Redirect stderr to LOG_FILE instead of /dev/null
- Log send attempt, success, and failure with timestamps
- Include target, channel, and error details in logs

### Fix 5: Extended Retry Logic

**File**: `worker-claude-queue.sh`
**Location**: Lines 137-159

**Change**:

- Increase max retries from 1 to 3
- Add "unable to connect" to retryable error patterns
- Implement exponential backoff (5s, 10s, 15s)
- Log each retry attempt

## Files Modified

| File                                                             | Changes     |
| ---------------------------------------------------------------- | ----------- |
| `claude-code-dispatch-macos/scripts/worker-claude-queue.sh`      | Fix 1, 5    |
| `claude-code-dispatch-macos/scripts/notify-openclaw-dispatch.sh` | Fix 2, 3, 4 |

## Validation Plan

1. **Manual Test**: Trigger test task, verify notification and logs
2. **Error Injection**: Simulate network failure, verify 3 retries
3. **Log Verification**: Check hook.log for success/failure messages
4. **Rollback Test**: `git revert` and verify system restoration

## Rollback Plan

All changes are reversible via `git revert`. No data migration required.

## Risk Assessment

| Risk                    | Mitigation                                 |
| ----------------------- | ------------------------------------------ |
| Race condition persists | Add small delay before notification        |
| Notification spam       | Dedupe logic preserved, only fixed timing  |
| Retry storm             | Exponential backoff limits retry frequency |
