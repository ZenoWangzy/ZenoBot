# macOS Self-Healing Gateway Design

> Design document for launchd-based self-healing OpenClaw gateway on macOS.
> Inspired by `openclaw-min-bundle` systemd architecture.

## Overview

This design translates the systemd-based self-healing architecture to macOS using launchd's native capabilities.

### Key Differences from Systemd

| Systemd Feature            | macOS launchd Equivalent       |
| -------------------------- | ------------------------------ |
| `OnFailure=fix.service`    | Watchdog polling + `kickstart` |
| `StartLimitBurst=5`        | State file failure counting    |
| `StartLimitIntervalSec=60` | Time-windowed failure tracking |
| `Restart=always`           | `KeepAlive: true`              |
| `EnvironmentFile`          | `EnvironmentVariables` dict    |

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    macOS Self-Healing Gateway Architecture               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────┐     ┌─────────────────────┐                    │
│  │   Gateway Agent     │     │   Watchdog Agent    │                    │
│  │ com.openclaw.gateway│     │com.openclaw.watchdog│                    │
│  ├─────────────────────┤     ├─────────────────────┤                    │
│  │ • KeepAlive: true   │◄────│ • Poll: 30s         │                    │
│  │ • ThrottleInterval  │     │ • Check failures    │                    │
│  │ • Restart: always   │     │ • Trigger fixer     │                    │
│  └─────────────────────┘     └──────────┬──────────┘                    │
│           │                             │                                │
│           │ failure                     │ kickstart                      │
│           ▼                             ▼                                │
│  ┌─────────────────────┐     ┌─────────────────────┐                    │
│  │   State Tracker     │     │   Fixer Agent       │                    │
│  │ ~/.local/state/...  │     │ com.openclaw.fixer  │                    │
│  ├─────────────────────┤     ├─────────────────────┤                    │
│  │ • exit-codes.json   │     │ • Oneshot           │                    │
│  │ • failure-count     │     │ • Claude Code       │                    │
│  │ • last-fix-time     │     │ • Max retries: 3    │                    │
│  └─────────────────────┘     └──────────┬──────────┘                    │
│                                          │                               │
│                                          ▼                               │
│                              ┌─────────────────────┐                    │
│                              │   Notifications     │                    │
│                              ├─────────────────────┤                    │
│                              │ • Discord DM        │                    │
│                              │ • Local file        │                    │
│                              └─────────────────────┘                    │
└──────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Gateway Agent (`com.openclaw.gateway.plist`)

Main OpenClaw gateway service.

- **KeepAlive: true** - Auto-restart on crash
- **ThrottleInterval: 10** - Rate limit restarts
- **ExitStatusChange: true** - Enable exit status tracking

### 2. Watchdog Agent (`com.openclaw.watchdog.plist`)

Monitors gateway health every 30 seconds.

- Checks if gateway is running
- Counts failures in 60s window
- Triggers fixer when threshold (3 failures) reached

### 3. Fixer Agent (`com.openclaw.fixer.plist`)

Oneshot service triggered by watchdog.

- Uses Claude Code to diagnose and fix issues
- Max 3 retry attempts
- Validates config before restart
- Sends notifications on success/failure

### 4. State Tracker

JSON file at `~/.local/state/openclaw/gateway-state.json`:

```json
{
  "failures": [1709654400, 1709654410, 1709654420],
  "last_fix": 1709654500,
  "fix_count": 5,
  "last_fix_status": "success"
}
```

## Failure Detection Flow

```
1. Gateway crashes
   └─ launchd restarts it (KeepAlive: true)

2. Gateway crashes again within 60s
   └─ Watchdog records failure timestamp

3. Gateway crashes 3rd time within 60s
   └─ Watchdog: "failure_count >= 3"
       └─ launchctl kickstart gui/UID/com.openclaw.fixer

4. Fixer runs:
   ├─ Collects error context
   ├─ Calls Claude Code with fix prompt
   ├─ Validates config JSON
   ├─ Restarts gateway
   └─ Sends notification (Discord + local file)

5. Success:
   └─ Clear failure count
       └─ Gateway resumes normal operation

   Failure:
   └─ Notification sent for manual intervention
```

## Security Model

- **No hardcoded secrets** - All sensitive values in `~/.config/openclaw/gateway.env`
- **File permissions** - `chmod 600` on env file
- **Single-instance fixer** - flock lock prevents parallel fix attempts
- **Config validation** - JSON validated before any restart

## Notifications

### Discord DM

Webhook-based notifications for fix events:

- Fix started
- Fix success (with attempt number)
- Fix failed (with error summary)

### Local File

Timestamped JSON files in `~/.local/state/openclaw/notifications/`:

- Persistent record of all fix attempts
- `latest.json` symlink to most recent

## Comparison with Systemd Version

| Feature           | Systemd                    | launchd               |
| ----------------- | -------------------------- | --------------------- |
| Failure trigger   | `OnFailure=` directive     | Watchdog polling      |
| Rate limiting     | `StartLimitBurst/Interval` | State file counting   |
| Service restart   | `Restart=always`           | `KeepAlive: true`     |
| Fixer activation  | systemd dependency         | `launchctl kickstart` |
| Detection latency | Immediate                  | Up to 30s             |

## Limitations

1. **Polling latency** - Up to 30s to detect repeated failures
2. **No native OnFailure** - Requires watchdog implementation
3. **State file dependency** - Could be corrupted (mitigated by validation)

## Future Improvements

1. **Apple Events** - Use `NSWorkspace` notifications for faster detection
2. **Metrics** - Export Prometheus metrics for monitoring
3. **Auto-backup** - Backup config before each fix attempt
4. **Fix templates** - Cache common fixes for faster recovery

---

_Design version: 1.0.0 | Created: 2026-03-05 | Author: Claude Code_
