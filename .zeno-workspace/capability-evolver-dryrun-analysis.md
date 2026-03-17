# Capability Evolver Dry-Run Analysis

**Date:** 2026-02-21
**Status:** READY_FOR_REVIEW

---

## 1. What Is NOT An Error

### `[injecting env (0)]` from dotenv

```
[dotenv@17.3.1] injecting env (0) from ../../.env
```

This is **expected behavior**, not an error:

- `dotenv` loads environment variables from `.env` files
- `(0)` indicates zero variables were loaded
- The `.env` file at `~/.agents/.env` exists but is **empty** (0 bytes)
- This is informational output from dotenvx, not a failure

**No action required.**

---

## 2. Actual Failure Causes

### Protocol Violations Detected

```
"protocol_violations": [
  "missing_or_invalid_mutation",
  "missing_or_invalid_personality_state"
]
```

### Root Cause Analysis

#### 2.1 Missing Evolution State File

The `solidify` command expects a state file at:

```
~/.agents/memory/evolution/evolution_solidify_state.json
```

This file **does not exist** because:

1. The state file is created by `evolve.run()`, not by `solidify`
2. Running `solidify --dry-run` directly **skips the evolve step**
3. Without prior evolution, there's no `last_run` state to solidify

#### 2.2 Expected State Structure

The `solidify` function (in `src/gep/solidify.js:825-846`) requires:

```javascript
const lastRun = state && state.last_run ? state.last_run : null;
// ...
const mutationRaw =
  lastRun && lastRun.mutation && typeof lastRun.mutation === "object" ? lastRun.mutation : null;
const personalityRaw =
  lastRun && lastRun.personality_state && typeof lastRun.personality_state === "object"
    ? lastRun.personality_state
    : null;

// Validation:
if (!mutation) protocolViolations.push("missing_or_invalid_mutation");
if (!personalityState) protocolViolations.push("missing_or_invalid_personality_state");
```

#### 2.3 Mutation Validation Requirements

A valid mutation must have (`src/gep/mutation.js:149-159`):

```javascript
{
  "type": "Mutation",
  "id": "mut_<timestamp>",
  "category": "repair" | "optimize" | "innovate",
  "trigger_signals": ["signal1", "signal2"],
  "target": "gene:xxx" | "behavior:protocol",
  "expected_effect": "description",
  "risk_level": "low" | "medium" | "high"
}
```

#### 2.4 Personality State Validation Requirements

A valid personality state must have (`src/gep/personality.js:70-80`):

```javascript
{
  "type": "PersonalityState",
  "rigor": 0.0-1.0,
  "creativity": 0.0-1.0,
  "verbosity": 0.0-1.0,
  "risk_tolerance": 0.0-1.0,
  "obedience": 0.0-1.0
}
```

#### 2.5 Secondary Issue: System Load Check

When attempting to run `evolve.run()`:

```
[Evolver] System load 3.51 exceeds max 2.0. Backing off 60000ms.
```

The evolver refused to run due to high system load (threshold: `EVOLVE_LOAD_MAX=2.0`).

---

## 3. Safe Operational Mode Recommendation

### Correct Execution Order

```
┌─────────────────────────────────────────────────────────────┐
│  1. evolve.run()     → Creates evolution_solidify_state.json │
│  2. solidify         → Reads state, commits evolution        │
└─────────────────────────────────────────────────────────────┘
```

### Two Supported Workflows

#### Workflow A: Full Evolution Cycle

```bash
cd ~/.agents/skills/capability-evolver
node index.js run          # Runs evolve, creates state file
node index.js solidify     # Commits the evolution
```

#### Workflow B: Manual Testing with Dry-Run

You need to **first create the state file** before dry-run solidify can work.

---

## 4. Concrete Fixes

### Fix 1: Create Memory Directory Structure

```bash
mkdir -p ~/.agents/memory/evolution
```

### Fix 2: Create Initial Personality State

```bash
cat > ~/.agents/memory/evolution/personality_state.json << 'EOF'
{
  "type": "PersonalityState",
  "rigor": 0.7,
  "creativity": 0.35,
  "verbosity": 0.25,
  "risk_tolerance": 0.4,
  "obedience": 0.85
}
EOF
```

### Fix 3: Create Minimum Valid State File

```bash
cat > ~/.agents/memory/evolution/evolution_solidify_state.json << 'EOF'
{
  "last_run": {
    "run_id": "manual_init_001",
    "created_at": "2026-02-21T00:00:00.000Z",
    "signals": ["manual_initialization"],
    "mutation": {
      "type": "Mutation",
      "id": "mut_manual_init",
      "category": "repair",
      "trigger_signals": ["manual_initialization"],
      "target": "behavior:protocol",
      "expected_effect": "initialize evolution state",
      "risk_level": "low"
    },
    "personality_state": {
      "type": "PersonalityState",
      "rigor": 0.7,
      "creativity": 0.35,
      "verbosity": 0.25,
      "risk_tolerance": 0.4,
      "obedience": 0.85
    },
    "personality_known": true,
    "selected_gene_id": null
  },
  "last_solidify": null
}
EOF
```

### Fix 4: Bypass Load Check for Testing

```bash
cd ~/.agents/skills/capability-evolver
EVOLVE_LOAD_MAX=10 node index.js run
```

### Fix 5: Run Full Evolution Cycle

```bash
cd ~/.agents/skills/capability-evolver

# Run evolve first (creates state file)
EVOLVE_LOAD_MAX=10 node index.js run

# Then run solidify dry-run
node index.js solidify --dry-run
```

### Fix 6: Alternative - One-Line Bootstrap

```bash
cd ~/.agents/skills/capability-evolver && \
mkdir -p ~/.agents/memory/evolution && \
cat > ~/.agents/memory/evolution/evolution_solidify_state.json << 'EOF'
{"last_run":{"run_id":"bootstrap","created_at":"2026-02-21T00:00:00Z","signals":["bootstrap"],"mutation":{"type":"Mutation","id":"mut_bootstrap","category":"repair","trigger_signals":["bootstrap"],"target":"behavior:protocol","expected_effect":"bootstrap initialization","risk_level":"low"},"personality_state":{"type":"PersonalityState","rigor":0.7,"creativity":0.35,"verbosity":0.25,"risk_tolerance":0.4,"obedience":0.85},"personality_known":true},"last_solidify":null}
EOF
```

---

## 5. Validation Checklist

After applying fixes, verify:

### 5.1 Directory Structure

```bash
ls -la ~/.agents/memory/evolution/
# Expected output:
# drwxr-xr-x  evolution/
# -rw-r--r--  evolution_solidify_state.json
# -rw-r--r--  personality_state.json (optional)
```

### 5.2 State File Validity

```bash
cd ~/.agents/skills/capability-evolver
node -e "
const fs = require('fs');
const path = require('path');
const { getEvolutionDir } = require('./src/gep/paths');
const { isValidMutation } = require('./src/gep/mutation');
const { isValidPersonalityState } = require('./src/gep/personality');

const statePath = path.join(getEvolutionDir(), 'evolution_solidify_state.json');
const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
const lastRun = state.last_run;

console.log('State file exists: YES');
console.log('last_run exists:', !!lastRun);
console.log('mutation valid:', isValidMutation(lastRun.mutation));
console.log('personality_state valid:', isValidPersonalityState(lastRun.personality_state));
"
```

Expected output:

```
State file exists: YES
last_run exists: true
mutation valid: true
personality_state valid: true
```

### 5.3 Dry-Run Success

```bash
cd ~/.agents/skills/capability-evolver
node index.js solidify --dry-run 2>&1 | grep -E "protocol_violations|SOLIDIFY"
```

Expected output should NOT contain:

- `missing_or_invalid_mutation`
- `missing_or_invalid_personality_state`

Should show:

```
[SOLIDIFY] SUCCESS  (or FAILED with different reason)
```

### 5.4 Full Cycle Test

```bash
cd ~/.agents/skills/capability-evolver

# Clean state (for fresh test)
rm -f ~/.agents/memory/evolution/evolution_solidify_state.json

# Run with elevated load threshold
EVOLVE_LOAD_MAX=10 node index.js run

# Verify state was created
ls ~/.agents/memory/evolution/evolution_solidify_state.json && echo "PASS: State file created"

# Run solidify
node index.js solidify --dry-run
```

---

## Summary

| Issue                                  | Cause                         | Fix                                                |
| -------------------------------------- | ----------------------------- | -------------------------------------------------- |
| `[injecting env (0)]`                  | Empty `.env` file             | None needed (informational)                        |
| `missing_or_invalid_mutation`          | No evolve run before solidify | Run `node index.js run` first or create state file |
| `missing_or_invalid_personality_state` | Same as above                 | Same as above                                      |
| System load backoff                    | Load > 2.0                    | Set `EVOLVE_LOAD_MAX=10`                           |

---

**READY_FOR_REVIEW**
