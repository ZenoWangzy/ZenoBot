# macOS Self-Healing Gateway Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the missing scripts, runbooks, and documentation for the macOS self-healing OpenClaw gateway.

**Architecture:** Three-agent pattern (Gateway + Watchdog + Fixer) using launchd services with state-based failure tracking.

**Tech Stack:** Bash scripts, launchd plists, JSON state files, Discord webhooks

---

## Prerequisites

- Existing launchd plists in `tools/openclaw-mac-bundle/launchd/`
- Design document at `docs/plans/2026-03-05-macos-self-healing-gateway-design.md`
- OpenClaw CLI installed at `~/.npm-global/lib/node_modules/openclaw/dist/index.js`

---

### Task 1: Create Scripts Directory

**Files:**

- Create: `tools/openclaw-mac-bundle/scripts/`

**Step 1: Create scripts directory**

```bash
mkdir -p tools/openclaw-mac-bundle/scripts
```

---

### Task 2: Implement Watchdog Script

**Files:**

- Create: `tools/openclaw-mac-bundle/scripts/openclaw-watchdog.sh`

**Step 1: Write the watchdog script**

Create a bash script that:

1. Checks if gateway service is running
2. Reads/writes failure state from JSON file
3. Counts failures within 60-second window
4. Triggers fixer via `launchctl kickstart` when threshold reached

**Key behaviors:**

- Exit 0: Gateway healthy
- Exit 1: Fixer triggered
- Logs to `~/.local/state/openclaw/logs/watchdog.log`

**Expected output:**

```
[WATCHDOG] Gateway status: running
[WATCHDOG] Failure count: 2/3 (window: 45s remaining)
```

---

### Task 3: Implement Fix Script

**Files:**

- Create: `tools/openclaw-mac-bundle/scripts/openclaw-fix.sh`

**Step 1: Write the fix script**

Create a bash script that:

1. Acquires flock lock (single-instance)
2. Collects error context from logs
3. Calls Claude Code with diagnostic prompt
4. Validates OpenClaw config JSON
5. Restarts gateway service
6. Sends Discord notification
7. Updates state file

**Key behaviors:**

- Max 3 retry attempts (configurable via env)
- 10-minute timeout for Claude Code
- Validates config before restart
- Creates notification file in `~/.local/state/openclaw/notifications/`

**Expected output:**

```
[FIXER] Starting repair attempt 1/3
[FIXER] Collected error context
[FIXER] Running Claude Code diagnosis...
[FIXER] Config validated successfully
[FIXER] Gateway restarted
[FIXER] Notification sent
```

---

### Task 4: Create Rollout Runbook

**Files:**

- Create: `tools/openclaw-mac-bundle/ROLLOUT.md`

**Step 1: Write the rollout runbook**

Document the deployment process:

1. Prerequisites check (Node.js, OpenClaw CLI)
2. Directory structure creation
3. Script installation
4. Launchd service installation
5. Service activation sequence
6. Verification steps

**Expected sections:**

- Pre-flight checklist
- Installation steps
- Service activation order
- Verification commands

---

### Task 5: Create Rollback Runbook

**Files:**

- Create: `tools/openclaw-mac-bundle/ROLLBACK.md`

**Step 1: Write the rollback runbook**

Document the uninstallation/rollback process:

1. Service deactivation order
2. Launchd service removal
3. Script cleanup
4. State file preservation (for debugging)
5. Verification of clean removal

**Expected sections:**

- Quick rollback (keep state)
- Full rollback (remove everything)
- Troubleshooting stuck services

---

### Task 6: Create Verification Checklist

**Files:**

- Create: `tools/openclaw-mac-bundle/VERIFICATION.md`

**Step 1: Write the verification checklist**

Create a comprehensive checklist:

1. Service status verification
2. Log file verification
3. Failure simulation test
4. Fixer trigger test
5. Notification delivery test

**Expected sections:**

- Automated checks (shell commands)
- Manual verification steps
- Failure injection tests
- Recovery validation

---

### Task 7: Create Bundle README

**Files:**

- Create: `tools/openclaw-mac-bundle/README.md`

**Step 1: Write the README**

Comprehensive documentation:

1. Overview and architecture
2. Quick start guide
3. Configuration options
4. File structure
5. Troubleshooting guide
6. Related documentation links

**Expected sections:**

- One-paragraph overview
- Architecture diagram (from design doc)
- Quick installation
- Configuration reference
- Common issues and fixes

---

## Implementation Order

1. **scripts/openclaw-watchdog.sh** - Core monitoring logic
2. **scripts/openclaw-fix.sh** - Repair automation
3. **ROLLOUT.md** - Deployment guide
4. **ROLLBACK.md** - Safe removal guide
5. **VERIFICATION.md** - Testing checklist
6. **README.md** - User documentation

## Verification Commands

After all tasks complete:

```bash
# Verify scripts exist and are executable
ls -la tools/openclaw-mac-bundle/scripts/*.sh

# Verify documentation exists
ls -la tools/openclaw-mac-bundle/*.md

# Quick syntax check
bash -n tools/openclaw-mac-bundle/scripts/openclaw-watchdog.sh
bash -n tools/openclaw-mac-bundle/scripts/openclaw-fix.sh
```

## Rollback Notes

- All new files are in `tools/openclaw-mac-bundle/`
- No existing files are modified
- Rollback: `rm -rf tools/openclaw-mac-bundle/scripts tools/openclaw-mac-bundle/*.md`

---

_Plan version: 1.0.0 | Created: 2026-03-05_
