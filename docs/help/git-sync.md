---
summary: "Cross-device Git sync policy for Win and Mac contributors"
read_when:
  - You work on the same repo from Windows and macOS
  - You maintain a fork and periodically sync from upstream
title: "Git Sync"
---

# Git Sync

Use this policy to keep `main` stable when the same repository is used from both Windows and macOS.

## One-time setup per machine

Run:

```bash
bash scripts/setup-git-policy.sh
```

On Windows (Git Bash), run:

```bash
bash scripts/setup-git-policy.sh --windows
```

What this script sets:

- `pull.rebase=true`
- `rebase.autoStash=false`
- `rerere.enabled=true`
- `fetch.prune=true`
- `push.default=simple`
- `core.hooksPath=git-hooks`
- `core.autocrlf=false` on Windows, `core.autocrlf=input` on macOS/Linux

## Daily workflow for `origin/main`

1. Before coding:

```bash
git fetch origin --prune
git rebase origin/main
```

2. Before pushing:

```bash
git fetch origin --prune
git rebase origin/main
git push origin main
```

3. Never run `pull`/`rebase` with uncommitted changes. Commit first.

## Upstream sync workflow for forks

When syncing from `upstream` into your fork:

1. Start from `origin/main` and ensure clean status.
2. Rebase local `main` onto `upstream/main`.
3. Run checks.
4. Push updated `main` to `origin`.

Commands:

```bash
git fetch origin --prune
git fetch upstream --prune
git rebase origin/main
git rebase upstream/main
pnpm check
git push origin main
```

If conflicts occur, resolve them once and continue with:

```bash
git add <resolved-files>
git rebase --continue
```

`rerere` will help reuse recorded conflict resolutions on future syncs.
