#!/usr/bin/env bash
cd "/Users/ZenoWang/.openclaw/workspace"
/Users/ZenoWang/.local/bin/claude -p "Write cc-osascript-test.txt with OSA_OK and then reply DONE" --permission-mode "bypassPermissions" > "/Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-output.txt" 2>&1
echo $? > "/Users/ZenoWang/.openclaw/workspace/claude-code-dispatch-macos/data/task-exit-code.txt"
