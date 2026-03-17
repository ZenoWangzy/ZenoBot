---
summary: "Common self-heal failure modes for gateway, agent, and Discord automation"
read_when:
  - Owning gateway self-heal or 30-second health checks
  - Changing launchd restart logic on macOS
  - Debugging false positives in gateway or Discord health probes
title: "Self-Heal Pitfalls"
---

# Self-Heal Pitfalls

This document captures the main failure modes we hit while running a 30-second
gateway self-heal loop on macOS. Read this before changing any health-check,
auto-fix, or launchd restart logic.

## Scope

These notes apply to the local gateway self-heal chain:

- `~/.openclaw/scripts/unified-health-check.sh`
- `scripts/openclaw-fix.sh`
- `~/Library/LaunchAgents/ai.openclaw.unified-health.plist`
- `~/Library/LaunchAgents/ai.openclaw.gateway.plist`

The current design goal is:

- detect `gateway`, `agent`, and `Discord` failures every 30 seconds
- try Claude Code CLI first
- fall back to a safe gateway restart only when needed
- avoid false positives that cause the repair loop itself to create outages

## Pitfall 1: Local probes can be poisoned by proxy environment variables

On this host, `launchd` exports proxy variables such as:

- `HTTP_PROXY`
- `HTTPS_PROXY`
- `ALL_PROXY`

If a local health probe hits `http://127.0.0.1:18789/health` without bypassing
proxies, `curl` may route the request through the proxy and return a false
failure such as `502 Bad Gateway`.

### Rule

Every loopback health probe must explicitly bypass proxies.

### Safe patterns

```bash
curl --noproxy "*" --max-time 5 "http://127.0.0.1:18789/health"
```

or:

```bash
env -u HTTPS_PROXY -u HTTP_PROXY -u ALL_PROXY \
  -u https_proxy -u http_proxy -u all_proxy \
  curl --max-time 5 "http://127.0.0.1:18789/health"
```

### Do not do this

```bash
curl "http://127.0.0.1:18789/health"
```

without an explicit proxy bypass.

## Pitfall 2: `launchctl bootout` is not a restart

We hit a broken restart path that did:

```bash
launchctl bootout gui/$UID/ai.openclaw.gateway
launchctl kickstart -k gui/$UID/ai.openclaw.gateway
```

That is unsafe for self-heal.

- `bootout` unloads the service from the `launchd` domain
- `kickstart -k` does not re-import a missing plist
- result: the repair loop can remove the gateway service and fail to bring it back

### Rule

Do not use `bootout` in the normal self-heal restart path.

### Safe restart sequence

If the service already exists:

```bash
launchctl kickstart -k "gui/$UID/ai.openclaw.gateway"
```

If the service is missing:

```bash
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
launchctl kickstart -k "gui/$UID/ai.openclaw.gateway"
```

Always verify that the label exists after `bootstrap`.

## Pitfall 3: Never compare mixed stdout/stderr logs by line order

An earlier Discord detector concatenated:

- `~/.openclaw/logs/gateway.log`
- `~/.openclaw/logs/gateway.err.log`

and then compared the last matching line number for:

- a Discord success signal
- a Discord failure signal

That is wrong because stderr was appended after stdout, so older errors could
appear later in the merged buffer than newer successes.

Result: Discord was already connected again, but the health check still reported
`discord disconnected or reconnect watchdog timeout`.

### Rule

When comparing events across multiple log files, compare timestamps, not merged
line positions.

### Current approach

- read the latest Discord success timestamp from `gateway.log`
- read the latest Discord error timestamp from `gateway.err.log`
- only treat Discord as unhealthy when the latest error is newer than the latest success

## Pitfall 4: Single-shot health failures are too noisy

Gateway restarts and short event-loop stalls can briefly fail `/health`.

If the 30-second monitor treats one failed probe as a hard outage, it will
trigger unnecessary Claude runs and restarts.

### Rule

Use a short recheck before declaring the gateway unhealthy.

### Current approach

- first probe fails
- sleep a short interval
- probe again
- only trigger self-heal if both probes fail

This keeps the check aggressive while filtering startup jitter.

## Pitfall 5: Claude failure and restart failure are different classes

A failed Claude self-heal does not always mean the gateway is unrecoverable.
Likewise, a failed restart does not always mean Claude chose the wrong fix.

### Rule

Track these separately:

- Claude execution success or timeout
- gateway re-registration success in `launchd`
- health endpoint recovery

The monitor should not silently assume that one implies the others.

## Pitfall 6: State files must be atomically rewritten

We hit a corrupted `health-state.json` caused by malformed multi-write output.
Once the state file is invalid JSON, the monitor can spam logs or make incorrect
decisions.

### Rule

State files must be written to a temp file and moved into place atomically.

## Operator Checklist

When the self-heal loop misbehaves, check these in order:

1. Is `ai.openclaw.gateway` present in `launchd`?
2. Does `curl --noproxy "*"` succeed against `127.0.0.1:18789/health`?
3. Is `Discord` actually connected in `openclaw channels status --probe`?
4. Is `health-state.json` valid JSON?
5. Did the monitor trigger because of a current failure, or because of stale log lines?
6. Did the fallback restart try to unload the service instead of reloading it safely?

## File Ownership

- `scripts/openclaw-fix.sh`
  - repo source of truth for fix logic
- `~/.openclaw/scripts/openclaw-fix.sh`
  - installed runtime copy actually used by the monitor
- `~/.openclaw/scripts/unified-health-check.sh`
  - installed 30-second monitor used by `launchd`
- `~/Library/LaunchAgents/ai.openclaw.unified-health.plist`
  - schedules the monitor every 30 seconds
- `~/Library/LaunchAgents/ai.openclaw.gateway.plist`
  - owns the gateway process in `launchd`

When you change restart or probe behavior, update both the repo script and the
installed runtime copy, or reinstall the monitor so the home copy stays aligned.

## Non-Negotiable Rules

- Always bypass proxies for loopback health probes.
- Never use `bootout` as the default self-heal restart path.
- Never compare mixed log streams by merged line order.
- Require a second probe before declaring the gateway dead.
- Verify `launchd` registration separately from process health.
- Keep the monitor narrow: only `gateway`, `agent`, and `Discord` should drive this loop.

For config migrations and repair flows, see [Doctor](/gateway/doctor).
