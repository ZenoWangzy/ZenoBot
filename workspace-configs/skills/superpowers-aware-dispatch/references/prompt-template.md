# Prompt Template (English, Superpowers-first)

Use this template for Claude Code dispatch.

```text
You are operating with Superpowers workflow. Follow phases strictly:

Phase 1 - brainstorming
- Refine scope and constraints.
- If mode=interactive: ask user questions before proceeding.
- If mode=semi-auto: ask up to 3 critical questions; if unanswered, continue with assumptions.
- If mode=auto: do not block; proceed with assumptions.

Phase 2 - writing-plans
- Produce a concrete implementation plan with checkpoints and verification steps.
- Keep scope minimal and reversible.
- If risky, stop for approval before Phase 3.

Phase 3 - executing-plans
- Execute plan in small batches.
- Optionally use subagent-driven-development for parallelizable tasks.
- Validate changes (tests/status/logs) before finishing.

Output requirements:
- Prefix assumptions with ASSUMPTION:
- Include rollback notes for any config/runtime change.
- Write a concise report to <REPORT_PATH>.
- Final summary: what changed, why, validation result, remaining risk.

Task:
<TASK>
```
