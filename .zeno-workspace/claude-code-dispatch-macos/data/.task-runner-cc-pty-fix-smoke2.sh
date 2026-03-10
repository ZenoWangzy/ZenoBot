#!/usr/bin/env bash
cd /Users/ZenoWang/.openclaw/workspace || exit 1
script -q /dev/null /Users/ZenoWang/.local/bin/claude -p Write\ cc-pty-fixed-smoke.txt\ with\ PTY_FIXED_OK\ and\ then\ reply\ DONE --permission-mode bypassPermissions  2>&1 | tee /Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-output.txt
ec=${PIPESTATUS[0]}
echo $ec > /Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-exit-code.txt
exit $ec
