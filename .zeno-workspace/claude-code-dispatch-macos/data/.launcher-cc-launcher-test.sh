#!/usr/bin/env bash
set -e
cd "/Users/ZenoWang/.openclaw/workspace"
# Run claude directly, output to files
/Users/ZenoWang/.local/bin/claude -p "Write cc-launcher-test.txt with LAUNCHER_OK and then reply DONE" --permission-mode "bypassPermissions" > "/Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-output.txt" 2>&1
echo $? > "/Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-exit-code.txt"
