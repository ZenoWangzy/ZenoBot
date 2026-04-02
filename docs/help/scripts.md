---
summary: "Repository scripts: purpose, scope, and safety notes"
read_when:
  - Running scripts from the repo
  - Adding or changing scripts under ./scripts
title: "Scripts"
---

# Scripts

The `scripts/` directory contains helper scripts for local workflows and ops tasks.
Use these when a task is clearly tied to a script; otherwise prefer the CLI.

## Conventions

- Scripts are **optional** unless referenced in docs or release checklists.
- Prefer CLI surfaces when they exist (example: auth monitoring uses `openclaw models status --check`).
- Assume scripts are host‑specific; read them before running on a new machine.

## Auth monitoring scripts

Auth monitoring scripts are documented here:
[/automation/auth-monitoring](/automation/auth-monitoring)

## Git policy setup script

Use `scripts/setup-git-policy.sh` to apply cross-device Git defaults in this repository.

- Sets rebase-first sync defaults (`pull.rebase`, `rerere`, `fetch.prune`, and `push.default`).
- Configures hooks with `core.hooksPath=git-hooks`.
- Applies platform-safe line ending policy (`--windows` sets `core.autocrlf=false`).

See the full workflow in [/help/git-sync](/help/git-sync).

## When adding scripts

- Keep scripts focused and documented.
- Add a short entry in the relevant doc (or create one if missing).
