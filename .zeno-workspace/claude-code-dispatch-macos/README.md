# Claude Code Dispatch (macOS + OpenClaw + Discord)

## 已完成配置

- Claude Code 路径: `/Users/ZenoWang/.local/bin/claude`
- Hook 脚本: `~/.claude/hooks/notify-openclaw-dispatch.sh`
- Claude Hook 事件: `Stop` + `SessionEnd`
- 结果目录: `~/.openclaw/workspace/claude-code-dispatch-macos/data`

## 一键派发

```bash
bash ~/.openclaw/workspace/claude-code-dispatch-macos/scripts/dispatch-claude.sh \
  -p "实现一个Python命令行todo" \
  -n "todo-cli" \
  -w ~/.openclaw/workspace \
  --agent-teams
```

默认回调到 Discord DM 目标 `853303202236858379`。

## 常用参数

- `--target <id>`: 改回调目标（Discord 用户/频道 id）
- `--channel discord`: 指定通道（默认 discord）
- `--permission-mode bypassPermissions|plan|acceptEdits`
- `--allowed-tools "Read,Bash,Edit,Write"`
- `--model <model>`
- `--claude-bin <path>`

## 文件

- `data/task-meta.json`: 当前任务元数据
- `data/task-output.txt`: Claude 输出
- `data/latest.json`: 完成结果（以 worker 写入为准）
- `data/hook.log`: hook 执行日志

## 状态真值规则（重要）

- **worker 是状态真值来源**：`run_id/worker_id/event` 由 worker 写入 `latest.json`。
- Hook 仅负责通知，不覆盖已有的 worker 最新状态（避免 `Stop` 覆盖 `ForcedStopAfterDeliverable`）。
- callback target 为空时自动回退到 owner：`853303202236858379`。
- 通知去重：按 `task + event + run_id + exit + output_hash` 去重，避免重复轰炸。

## 校验 Claude 路径

```bash
bash ~/.openclaw/workspace/claude-code-dispatch-macos/scripts/check-claude-path.sh
```
