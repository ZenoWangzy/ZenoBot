# USER.md - About Your Human

_Learn about the person you're helping. Update this as you go._

- **Name:** 王泽宇 / zeno
- **What to call them:** master (from zenomacbot config), or zeno
- **Pronouns:** he/him
- **Timezone:** Asia/Shanghai
- **Notes:** 肉身、意识、精神的结合体. ENTJ - strategic, business-focused.

## Context

**From zenomacbot-backup:**

- Core Goal: 功成名就，建立对世界的影响力
- Values: 影响力 > 金钱, 长期价值 > 短期利益
- MBTI: ENTJ - 战略家
- Resilient, goal-oriented, pragmatic
- Has two girlfriends who know each other
- Entrepreneurial mindset: wants to build value networks that empower others

**Recent Context (2026-02-11):**

- Connected to Discord
- Has GitHub CLI installed (username: ZenoWangzy)
- Has zenomacbot-backup repo with extensive configuration
- Asked to rename agent to "MyAssistant"

**Workflow Preferences (2026-02-19):**

- Default role is supervisor; prefer delegating execution work to Claude Code CLI instead of direct local tool operations.
- In Zeno OpenClaw Skill Kit workflow: use Claude Code CLI for implementation; if bugs occur, use Codex CLI for bug-fixing.
- Prefers staged process: brainstorm → plan → execute, with review checkpoints.
- Gemini CLI is available and user is logged in; can be used when helpful.
- **Process visibility (hard rule):** In Discord, for any multi-step task, send real-time progress updates step-by-step (one message per completed step). Do not wait and dump only a final summary.
- **Execution default (hard rule):** Default to delegating non-trivial implementation/execution tasks to CC CLI (Claude Code). Only execute directly when the task is truly simple.
- **CC auto-run preference (hard rule):** For CC-dispatched work, prefer automatic execution with minimal restrictions, retry up to 3 times on recoverable failures, and deliver progress/results via Discord DM + local report file.
- **CC error recovery rule (hard rule):** If a prior CC CLI run errors with "unable to connect", immediately issue `continue` to resume/continue the CC workflow before declaring failure.
- **CC full-permission flag rule (hard rule):** For all Claude CLI commands, always include `--dangerously-skip-permissions` so CC CLI runs with full permissions.
- **Deferred-action execution rule (hard rule):** Whenever I say “I’ll handle this in N minutes” (or any explicit delayed follow-up), I must schedule execution via cron or a watcher mechanism (not memory-only/manual waiting), then cancel/cleanup the scheduled task after completion.
- **Post-dispatch polling rule (hard rule):** After dispatching ANY CC CLI / Codex CLI task, immediately create a 5-minute cron progress-check reminder (or equivalent watcher). Keep reporting every 5 minutes until completion; when there are no active CC/Codex tasks, cancel/cleanup all related reminder jobs.
- **CC/Codex progress reminder delivery rule (hard rule):** Any 5-minute progress reminder for an active CC CLI / Codex CLI task must be sent outward as a visible Discord progress update to the user. Do not treat such reminders as internal-only, even if reminder/system wording suggests internal handling.
- **Async task watcher hook rule (hard rule):** When dispatching CC CLI / Codex CLI async tasks, MUST hook a watcher that checks task status every 5 minutes and reports to Discord. This is NOT optional. The watcher continues until task completion. If the dispatch system has built-in watcher (e.g., `watch-cc-task.sh`), verify it's active; if not, create external cron-based watcher. Never dispatch async tasks without progress visibility.

_(What do they care about? What projects are they working on? What annoys them? What makes them laugh? Build this over time.)_

## Environment

- GitHub CLI: Installed (available via `gh` command)

---

The more you know, the better you can help. But remember — you're learning about a person, not building a dossier. Respect the difference.
