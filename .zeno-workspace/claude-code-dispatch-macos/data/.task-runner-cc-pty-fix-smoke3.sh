#!/usr/bin/env bash
cd /Users/ZenoWang/.openclaw/workspace || exit 1
/Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/scripts/claude-pty-run.py /Users/ZenoWang/.openclaw/workspace /Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-output.txt /Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-exit-code.txt /Users/ZenoWang/.local/bin/claude -p Write\ cc-pty-fixed-smoke3.txt\ with\ PTY_FIXED_OK\ and\ then\ reply\ DONE --permission-mode bypassPermissions 
ec=$?
exit $ec
