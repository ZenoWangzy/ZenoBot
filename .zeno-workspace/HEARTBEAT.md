# HEARTBEAT.md - 定期检查任务

执行以下检查。如果都正常，回复 HEARTBEAT_OK。

## 1. Coding Agent 任务状态（必须检查）

检查是否有正在运行的 CC CLI 或 Codex CLI 任务：

- 读取 `~/.openclaw/workspace/claude-code-dispatch-macos/data/task-meta.json`
- 如果 `status == "running"`，向用户汇报任务名称和已运行时间
- 如果运行超过 10 分钟，提醒用户关注

## 2. 消息投递检查

如果用户最近 30 分钟内发过消息：

- 检查最后一条用户消息是否有对应的文本回复（不是 toolCall）
- 如果没有回复内容，说明可能投递失败，报告异常

---

**规则：**

- 深夜 (23:00-08:00) 保持安静，除非有异常
- 发现异常必须汇报，不能只回 HEARTBEAT_OK
- 汇报要简洁
