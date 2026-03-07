# Claude Code Dispatch - 最小闭环监控系统

> 让任务执行过程可见，不再失联。

## 目标

实现 4 个核心功能：

1. **Start Hook** - 任务启动时立即通知
2. **5分钟 Progress Watcher** - 定期汇报进度
3. **Completion Hook** - 任务完成时通知
4. **Failure Hook** - 任务失败时通知

## 目录结构

```
claude-code-dispatch-macos/
├── data/
│   ├── running/          # 正在运行的任务
│   │   └── <run_id>/
│   │       ├── meta.json        # 任务元数据
│   │       ├── heartbeat.json   # 心跳状态
│   │       ├── task-output.txt  # 任务输出
│   │       └── watcher.pid      # watcher 进程 ID
│   └── done/             # 已完成任务（归档）
│       └── <run_id>/
├── scripts/
│   ├── hooks/
│   │   ├── on-start.sh      # 开始 Hook
│   │   ├── on-complete.sh   # 完成 Hook
│   │   ├── on-failure.sh    # 失败 Hook
│   │   └── notify.sh        # 通知模块
│   ├── watcher/
│   │   ├── progress-watch.sh       # Progress Watcher 主循环
│   │   └── spawn-progress-watch.sh # 启动 Watcher
│   └── lib/
│       ├── json.sh          # JSON 工具
│       ├── run-state.sh     # 运行状态管理
│       └── clock.sh         # 时间工具
└── tests/
    ├── test-long-success.sh # 长任务成功测试
    ├── test-long-failure.sh # 长任务失败测试
    └── test-short-task.sh   # 秒完成测试
```

## 快速开始

### 1. 环境要求

- Bash 4.0+
- [jq](https://stedolan.github.io/jq/) - JSON 处理
- curl - 发送通知

### 2. 配置

```bash
# 设置 Discord Webhook（可选）
export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."

# 设置通知渠道（默认 discord）
export NOTIFY_CHANNEL="discord"  # 或 "stdout" 用于测试

# 设置进度通知间隔（默认 300 秒 = 5 分钟）
export PROGRESS_INTERVAL_SEC=300
```

### 3. 使用

#### 启动任务

```bash
# 方式 1：自动生成 run_id
./scripts/hooks/on-start.sh "my-task-name"

# 方式 2：指定 run_id
./scripts/hooks/on-start.sh "my-task-name" "custom-run-id"

# 输出：run_id
```

#### 任务完成

```bash
./scripts/hooks/on-complete.sh "<run_id>" "任务摘要"
```

#### 任务失败

```bash
./scripts/hooks/on-failure.sh "<run_id>" "<exit_code>"
```

## 数据模型

### meta.json

```json
{
  "task_name": "cc-doc-optimize",
  "run_id": "1772871000-cc-doc-optimize",
  "status": "running",
  "created_at": 1772871000,
  "started_at": 1772871005,
  "updated_at": 1772871005,
  "notify": {
    "start_sent": false,
    "last_progress_at": 0,
    "completion_sent": false,
    "failure_sent": false
  },
  "watcher": {
    "enabled": true,
    "interval_sec": 300,
    "pid": null
  },
  "result": {
    "exit_code": null,
    "summary": null
  }
}
```

### heartbeat.json

```json
{
  "last_output_mtime": 1772871100,
  "last_output_size": 812,
  "last_seen_at": 1772871100,
  "last_progress_sent_at": 0
}
```

## 通知格式

### 开始通知

```
🚀 **步骤 1/4：已开始**
- **任务**: cc-doc-optimize
- **run_id**: `1772871000-cc-doc-optimize`
- **开始时间**: 2026-03-07 16:30:00
- **进度检查间隔**: 5 分钟
```

### 进度通知

```
⏳ **进度更新**
- **任务**: cc-doc-optimize
- **run_id**: `1772871000-cc-doc-optimize`
- **运行时长**: 5m 30s
- **状态**: 有新输出
```

### 完成通知

```
✅ **步骤 4/4：已完成**
- **任务**: cc-doc-optimize
- **run_id**: `1772871000-cc-doc-optimize`
- **运行时长**: 11m 0s
- **结果**: 成功
```

### 失败通知

```
❌ **任务失败**
- **任务**: cc-doc-optimize
- **run_id**: `1772871000-cc-doc-optimize`
- **运行时长**: 7m 0s
- **Exit Code**: 1
- **错误摘要**:
```

ERROR: Something went wrong

```
- **建议**: 人工检查或重试
```

## 测试

```bash
# 运行所有测试（注意：长任务测试需要 11+ 分钟）

# 秒完成测试（10 秒）
./tests/test-short-task.sh

# 长任务成功测试（11 分钟）
./tests/test-long-success.sh

# 长任务失败测试（7 分钟）
./tests/test-long-failure.sh
```

## 幂等保护

所有 Hook 都是幂等的：

- **Start** - 只发送一次开始通知
- **Progress** - 间隔至少 5 分钟
- **Completion** - 只发送一次完成通知
- **Failure** - 只发送一次失败通知

重复调用 Hook 不会产生重复通知。

## 边界处理

- ✅ 重复 Hook 调用 → 幂等跳过
- ✅ Watcher PID 存在但进程已死 → 自动重启
- ✅ 极短任务（秒完成）→ 不发送进度，直接完成
- ✅ 输出文件不存在 → 优雅处理

## 下一步（Phase 2）

本版本**不做**：

- 自动错误恢复（continue）
- Re-dispatch
- Duplicate 检测
- Lease 竞争控制
- 多 watcher 协调
- 智能摘要

这些将在 Phase 2 实现。

## License

MIT
