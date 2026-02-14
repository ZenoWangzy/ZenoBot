# Windows Gateway Keepalive Design

> Date: 2026-02-15
> Status: Approved

## Problem

On Windows, the OpenClaw gateway process does not automatically restart after:
1. Process crash
2. Network disconnection recovery
3. System reboot (only starts once at login)

macOS uses LaunchAgent with `KeepAlive: true`, which handles all these cases. Windows Scheduled Task only triggers on login with no restart capability.

## Solution

Enhance Windows Scheduled Task with a watchdog mechanism:

- Add repeat trigger (every 1 minute) to Scheduled Task
- Create a lightweight watchdog script that checks if gateway is running
- If gateway port (18789) is not listening, start gateway
- Platform-isolated: only affects Windows, no impact on macOS

## Architecture

```
User Login
    │
    ▼
Scheduled Task Trigger
    │
    ▼
watchdog.cmd ──► Check port 18789
    │                    │
    │              ┌─────┴─────┐
    │              │           │
    │           Running    Not Running
    │              │           │
    │              │           ▼
    │              │      Start gateway
    │              │           │
    │              └─────┬─────┘
    │                    │
    ▼                    ▼
Repeat every 1min ◄──────┘
```

## File Changes

| File | Change |
|------|--------|
| `src/daemon/schtasks.ts` | Add repeat trigger (`/RI 1`) and call watchdog |
| `src/daemon/watchdog.ts` | New file - port check and gateway startup (Windows only) |
| `src/daemon/index.ts` | Export watchdog if needed |

## Implementation Details

### schtasks.ts Changes

```typescript
// Add repeat interval parameter
const repeatArgs = ["/RI", "1"]; // Repeat every 1 minute

// Task runs watchdog instead of gateway directly
const scriptContent = `
@echo off
cd /d "${workingDir}"
node "${watchdogPath}" --port ${port}
`;
```

### watchdog.ts

```typescript
// Windows only
if (process.platform !== "win32") {
  process.exit(0);
}

// Check if port is listening
async function isGatewayRunning(port: number): Promise<boolean> {
  // Use netstat or socket connection test
}

// Start gateway if not running
async function ensureGatewayRunning(): Promise<void> {
  if (!await isGatewayRunning(port)) {
    // Spawn gateway process
  }
}
```

## Platform Isolation

All changes are wrapped in platform checks:

```typescript
if (process.platform !== "win32") {
  return;
}
```

macOS LaunchAgent code remains completely untouched.

## Discord Connection

No changes needed - existing code already has:
- 50 reconnection attempts
- Exponential backoff
- Connection stall detection

The watchdog ensures gateway is running; Discord.js handles reconnection.

## Success Criteria

1. Gateway automatically restarts within 1 minute of crash
2. Gateway starts automatically on system boot
3. No changes to macOS functionality
4. Code syncs between Windows and macOS without conflicts
