#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/Users/ZenoWang/.openclaw/workspace"
cd "$WORKDIR"

STASHED=0
STASH_REF=""

cleanup() {
  if [[ "$STASHED" == "1" && -n "$STASH_REF" ]]; then
    if ! git stash pop --index -q "$STASH_REF"; then
      echo "[WARN] stash pop had conflicts. Resolve manually. stash=$STASH_REF"
      exit 2
    fi
  fi
}
trap cleanup EXIT

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git stash push -u -m "sync-private-auto-stash-$(date +%s)" >/dev/null
    STASH_REF="stash@{0}"
    STASHED=1
  fi

  git pull --rebase
fi

mkdir -p "$WORKDIR/private"
cp -f /Users/ZenoWang/.openclaw/openclaw.json "$WORKDIR/private/openclaw.json"
cp -f "$WORKDIR/SOUL.md" "$WORKDIR/private/SOUL.md"
cp -f "$WORKDIR/USER.md" "$WORKDIR/private/USER.md"
cp -f "$WORKDIR/IDENTITY.md" "$WORKDIR/private/IDENTITY.md"
cp -f "$WORKDIR/MEMORY.md" "$WORKDIR/private/MEMORY.md"
mkdir -p "$WORKDIR/private/memory"
cp -f "$WORKDIR"/memory/*.md "$WORKDIR/private/memory/" 2>/dev/null || true

git add -A
if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

TS=$(date '+%Y-%m-%d %H:%M:%S')
git commit -m "sync: auto $TS"
git push

echo "sync-private: done"
