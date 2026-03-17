# CC Superpowers Orchestration Methodology Report

> **Task:** sp-orchestration-tweet-deep (Retry #2/3)
> **Status:** Research Complete
> **Date:** 2026-03-05

---

## Executive Summary

The Superpowers orchestration methodology is a structured software development workflow designed for AI coding agents. It enforces a strict 3-phase process (brainstorming → planning → execution) with mandatory skill invocations, preventing premature implementation and ensuring quality through systematic reviews.

---

## 1. Core Philosophy

| Principle                   | Description                                    |
| --------------------------- | ---------------------------------------------- |
| **Test-Driven Development** | Write tests first, always (RED-GREEN-REFACTOR) |
| **Systematic over ad-hoc**  | Process over guessing                          |
| **Complexity reduction**    | Simplicity as primary goal                     |
| **Evidence over claims**    | Verify before declaring success                |

**Key insight:** Skills are mandatory, not suggestions. The agent must check for relevant skills before any task.

---

## 2. The 3-Phase Workflow

### Phase 1: Brainstorming (`brainstorming` skill)

**Purpose:** Refine rough ideas into fully formed designs through Socratic dialogue.

**Process:**

1. **Explore project context** — check files, docs, recent commits
2. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
3. **Propose 2-3 approaches** — with trade-offs and recommendation
4. **Present design** — in sections, get user approval after each
5. **Write design doc** — save to `docs/plans/YYYY-MM-DD-<topic>-design.md`
6. **Transition to implementation** — invoke `writing-plans` skill

**Hard Gate:** Do NOT write any code until design is approved.

**Anti-pattern:** "This is too simple to need a design" — every project goes through this process.

---

### Phase 2: Writing Plans (`writing-plans` skill)

**Purpose:** Create bite-sized implementation plans (2-5 minute tasks each).

**Plan Document Header:**

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans

**Goal:** [One sentence]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]
```

**Task Structure:**

```markdown
### Task N: [Component Name]

**Files:**

- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Step 1: Write the failing test**
**Step 2: Run test to verify it fails**
**Step 3: Write minimal implementation**
**Step 4: Run test to verify it passes**
**Step 5: Commit**
```

**Remember:**

- Exact file paths always
- Complete code in plan (not "add validation")
- DRY, YAGNI, TDD, frequent commits

---

### Phase 3: Executing Plans

**Two execution modes:**

#### 3a. Subagent-Driven Development (same session)

- Fresh subagent per task
- Two-stage review after each: spec compliance first, then code quality
- Faster iteration (no human-in-loop between tasks)

```
Per Task:
1. Dispatch implementer subagent
2. Implementer implements, tests, commits, self-reviews
3. Dispatch spec reviewer subagent → verify spec compliance
4. Dispatch code quality reviewer subagent → verify quality
5. Mark task complete in TodoWrite
```

#### 3b. Batch Execution with Checkpoints (parallel session)

- Load plan, review critically
- Execute tasks in batches (default: first 3)
- Report for review between batches
- Human provides feedback, continue

---

## 3. Parallel Agent Dispatch

**When to use:** 2+ independent tasks without shared state or sequential dependencies.

**Pattern:**

```
Agent 1 → Fix file-a.test.ts
Agent 2 → Fix file-b.test.ts
Agent 3 → Fix file-c.test.ts
```

**Agent prompt requirements:**

1. **Focused** — One clear problem domain
2. **Self-contained** — All context needed
3. **Specific about output** — What should agent return?

**Don't use when:**

- Failures are related (fix one might fix others)
- Need to understand full system state
- Agents would interfere with each other

---

## 4. Skill Priority & Types

**Priority order:**

1. **Process skills first** (brainstorming, debugging) — determine HOW to approach
2. **Implementation skills second** (frontend-design, mcp-builder) — guide execution

**Skill types:**

- **Rigid** (TDD, debugging): Follow exactly
- **Flexible** (patterns): Adapt principles to context

---

## 5. Red Flags (Rationalization Patterns)

| Thought                             | Reality                                        |
| ----------------------------------- | ---------------------------------------------- |
| "This is just a simple question"    | Questions are tasks. Check for skills.         |
| "I need more context first"         | Skill check comes BEFORE clarifying questions. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first.   |
| "This doesn't need a formal skill"  | If a skill exists, use it.                     |
| "The skill is overkill"             | Simple things become complex. Use it.          |

---

## 6. Integration with OpenClaw Dispatch

The `openclaw-cc-superpowers-kit` provides CLAW.md for orchestration:

```markdown
## Execution Policy

- Prompt to CC must be in English
- For unattended runs, block AskUserQuestion
- Use assumptions instead of blocking interviews
- Keep edits minimal and reversible

## Standard Orchestration

Stage 1 — Brainstorm only → discord-brainstorm.md
Stage 2 — Plan only → \*.plan.md
Stage 3 — Execute only → validation evidence + rollback notes
```

**Watchdog expectations:**

- Notify on timeout, stall, API/network error, non-zero exit
- Defaults: 30 min timeout, 8 min stall detection

---

## 7. Complete Skills Library

| Category          | Skill                          | Purpose                              |
| ----------------- | ------------------------------ | ------------------------------------ |
| **Testing**       | test-driven-development        | RED-GREEN-REFACTOR cycle             |
| **Debugging**     | systematic-debugging           | 4-phase root cause process           |
|                   | verification-before-completion | Ensure it's actually fixed           |
| **Collaboration** | brainstorming                  | Socratic design refinement           |
|                   | writing-plans                  | Detailed implementation plans        |
|                   | executing-plans                | Batch execution with checkpoints     |
|                   | subagent-driven-development    | Fast iteration with two-stage review |
|                   | dispatching-parallel-agents    | Concurrent subagent workflows        |
|                   | requesting-code-review         | Pre-review checklist                 |
|                   | receiving-code-review          | Responding to feedback               |
|                   | using-git-worktrees            | Parallel development branches        |
|                   | finishing-a-development-branch | Merge/PR decision workflow           |
| **Meta**          | writing-skills                 | Create new skills                    |
|                   | using-superpowers              | Introduction to the skills system    |

---

## 8. Key Takeaways for Automation

1. **Skill invocation is mandatory** — Even 1% chance means invoke
2. **Process before implementation** — Never skip phases
3. **Two-stage review** — Spec compliance first, then code quality
4. **Bite-sized tasks** — 2-5 minutes each with exact file paths
5. **Evidence over claims** — Verify before declaring success
6. **Assumptions over blocking** — In auto mode, proceed with assumptions

---

## 9. Task Recovery Notes

**Original task:** sp-orchestration-tweet-deep
**Retry count:** 2 of 3
**Blockers:** API connectivity failures
**Resolution:** This report completes the research phase

**Rollback notes:** No implementation changes made — report only.

---

## References

- Superpowers Plugin: `~/.claude/plugins/cache/claude-plugins-official/superpowers/4.3.1/`
- OpenClaw Kit: `~/.openclaw/workspace/openclaw-cc-superpowers-kit/CLAW.md`
- GitHub: https://github.com/obra/superpowers

---

_Report generated: 2026-03-05 10:38 CST_
