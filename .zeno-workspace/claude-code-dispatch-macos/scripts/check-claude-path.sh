#!/usr/bin/env bash
set -euo pipefail

echo "which claude: $(command -v claude || echo 'not found')"
if command -v claude >/dev/null 2>&1; then
  echo "claude --version:"
  claude --version || true
fi

echo "default configured path: ${CLAUDE_BIN:-$HOME/.local/bin/claude}"
if [ -x "${CLAUDE_BIN:-$HOME/.local/bin/claude}" ]; then
  echo "configured binary exists ✅"
else
  echo "configured binary missing ❌"
fi
