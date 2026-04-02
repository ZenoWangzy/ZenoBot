#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/setup-git-policy.sh [--windows|--mac|--linux] [--global]

Applies Git sync policy for this repository by default.
- Default scope: repository local config
- Optional scope: --global for user-level config
EOF
}

scope="--local"
platform="auto"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --windows)
      platform="windows"
      ;;
    --mac)
      platform="mac"
      ;;
    --linux)
      platform="linux"
      ;;
    --global)
      scope="--global"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: run this script inside a Git repository." >&2
  exit 1
fi

if [[ "$platform" == "auto" ]]; then
  uname_value="$(uname -s 2>/dev/null || echo "")"
  case "$uname_value" in
    MINGW*|MSYS*|CYGWIN*)
      platform="windows"
      ;;
    Darwin)
      platform="mac"
      ;;
    *)
      platform="linux"
      ;;
  esac
fi

git config "$scope" pull.rebase true
git config "$scope" rebase.autoStash false
git config "$scope" rerere.enabled true
git config "$scope" fetch.prune true
git config "$scope" push.default simple
git config "$scope" core.hooksPath git-hooks

if [[ "$platform" == "windows" ]]; then
  git config "$scope" core.autocrlf false
else
  git config "$scope" core.autocrlf input
fi

if git show-ref --verify --quiet refs/remotes/origin/main; then
  git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
fi

echo "Applied Git policy:"
echo "- scope: $scope"
echo "- platform: $platform"
echo "- pull.rebase=$(git config --get pull.rebase)"
echo "- rebase.autoStash=$(git config --get rebase.autoStash)"
echo "- rerere.enabled=$(git config --get rerere.enabled)"
echo "- fetch.prune=$(git config --get fetch.prune)"
echo "- push.default=$(git config --get push.default)"
echo "- core.hooksPath=$(git config --get core.hooksPath)"
echo "- core.autocrlf=$(git config --get core.autocrlf)"
