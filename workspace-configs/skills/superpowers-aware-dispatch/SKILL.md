---
name: superpowers-aware-dispatch
description: Dispatch Claude Code tasks with Superpowers workflow (brainstorming → writing-plans → executing-plans/subagent-driven-development) plus async hook callbacks. Use when tasks are complex, long-running, need stable background execution, or require explicit plan-first behavior and human checkpoints.
---

# Superpowers-Aware Dispatch

Use this skill to run Claude Code with strict Superpowers flow and OpenClaw async callbacks.

## Workflow Modes

- **interactive**: Ask user questions during brainstorming before planning.
- **semi-auto (default)**: Ask at most 3 critical questions, then proceed with explicit assumptions.
- **auto**: Do not block on questions. Continue with assumptions and mark risks.

## Required Execution Pattern

1. Build an English prompt from `references/prompt-template.md`.
2. Include explicit Superpowers phases in prompt:
   - brainstorming
   - writing-plans
   - executing-plans (or subagent-driven-development)
3. Dispatch via script:
   - `scripts/dispatch-superpowers.sh`
4. Do not poll aggressively. Wait for hook callback (`latest.json` / channel message).
5. On completion, summarize:
   - outcomes
   - assumptions used
   - risks
   - rollback notes

## Human Interview Handling (Brainstorming)

When brainstorming wants user interviews:

- In **interactive** mode: forward questions to user and recommend 2-3 options.
- In **semi-auto** mode: ask only high-impact questions (scope, constraints, success criteria). If unanswered, continue with assumptions.
- In **auto** mode: continue immediately using assumptions and label them `ASSUMPTION:` in outputs.

Never stall background jobs forever waiting for user input.

## Reliability Guardrails

Use watchdog-enabled dispatch scripts so abnormal states are surfaced immediately:

- timeout
- output stall
- API/network error patterns
- non-zero process exit

For unattended runs, block `AskUserQuestion` via Claude hook and emit an OpenClaw wake event instead.

## Command

```bash
bash /Users/ZenoWang/.openclaw/skills/superpowers-aware-dispatch/scripts/dispatch-superpowers.sh \
  --task "<task>" \
  --name "<task-name>" \
  --workdir "<dir>" \
  --mode semi-auto \
  --agent-teams
```

## Defaults

- Prompt language: **English**
- Mode: `semi-auto`
- Permission: `bypassPermissions`
- Callback target: Discord DM `853303202236858379`

## Safety

- Keep changes minimal and reversible.
- Prefer config edits with explicit rollback steps.
- Avoid unrelated refactors.
- If task is risky, require plan approval before execution.
