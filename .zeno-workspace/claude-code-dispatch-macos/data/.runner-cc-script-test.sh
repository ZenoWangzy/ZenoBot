#!/usr/bin/env bash
set -e
cd "/Users/ZenoWang/.openclaw/workspace"
exec /Users/ZenoWang/.local/bin/claude -p "Write cc-script-test.txt with SCRIPT_OK and then reply DONE" --permission-mode "bypassPermissions"
