# 任务进度监控系统实施计划

> 日期：2026-03-06
> 状态：设计中
> 目标：为 Discord -> Gateway Agent -> ACP / Subagent / 本地 CLI fallback 这条异步 coding 任务链路补齐“强制登记、5 分钟进度回报、失败显式通知、重启恢复”四项能力。

## 背景

当前链路已经具备异步派发的基础能力，但没有形成可靠闭环：

- ACP 线程绑定能力存在，但依赖显式配置，未开启时会直接失败。
- Subagent 生命周期有 hook，但 ACP 与本地 CLI fallback 没有统一的任务登记层。
- 任务一旦进入长时间运行或无输出状态，用户侧容易出现“静默”。
- Gateway 重启时虽然会尽量 drain active tasks，但还没有和“任务进度回报”形成一致的恢复语义。

这导致用户感知上出现三个问题：

1. 任务是否真的派发了，不透明。
2. 任务运行中是否卡住，不透明。
3. 任务被中断或失败时，没有稳定的补发说明。

本计划的目标不是引入复杂编排系统，而是在现有 OpenClaw 架构上补一层最小但可靠的任务监控面。

## 目标

- 任何异步 coding agent 任务，只要进入 `accepted` / `running`，就必须被登记。
- 任务运行超过 5 分钟仍未结束时，自动向原线程发送进度回报。
- 任务失败、被取消、被 Gateway 重启打断时，必须向原线程发送显式状态。
- Gateway 重启后可以恢复运行中任务的监控，不出现“任务仍在跑，但 watcher 丢了”的情况。
- 方案同时覆盖三类异步入口：
  - ACP 会话
  - OpenClaw subagent
  - 本地 CLI backend / fallback，例如 `claude -p`、`codex exec`

## 非目标

- 不在第一阶段实现真正的 token-level 流式实时 UI。
- 不在第一阶段实现每个任务独立的 cron job。
- 不在第一阶段做复杂的多租户任务队列或分布式锁。
- 不把“无输出”误判为“失败”；第一阶段先标记为 `stalled` 或 `running-no-output`。

## 设计原则

### 1. 强制登记，而不是依赖调用方自觉

不能依赖 agent prompt 或调用路径“记得创建 watcher”。必须在共享异步入口统一建档。

### 2. 单一 watcher，而不是一任务一 cron

每个任务单独创建 cron job 会带来清理难、重复调度、重启恢复复杂的问题。更合理的方案是：

- 只维护一个全局 watcher
- 由 watcher 扫描所有 `running` 任务
- 按 `lastProgressAt` 判断是否需要发送 5 分钟进度

### 3. 任务状态持久化优先

进度监控不能只放在内存里。必须持久化到磁盘，才能支撑 Gateway 重启恢复。

### 4. 明确区分“运行中”和“已卡住”

进程仍活着但长期无输出，与“已退出”不是一回事。状态机要能表达两者差异。

## 总体架构

```text
Discord message / agent request
  -> 异步派发入口（ACP / subagent / CLI fallback）
  -> TaskRegistry.create()
  -> 任务开始执行
  -> ProgressWatcher 定时扫描 running tasks
  -> 满 5 分钟未回报则发进度消息
  -> 任务结束 / 失败 / 取消 / 中断
  -> TaskRegistry.complete()/fail()/interrupt()
  -> 发送最终状态消息
```

### 组件划分

1. `TaskRegistry`

- 职责：创建、读取、更新、完成、恢复任务状态
- 存储：持久化 JSON 文件
- 范围：所有异步 coding 任务共享

2. `ProgressWatcher`

- 职责：周期性扫描 `running` 任务并决定是否发送进度
- 运行方式：优先集成到 Gateway 内部服务；备选为单一 cron job

3. `TaskLifecycle Integrations`

- 职责：在 ACP、subagent、本地 CLI fallback 入口统一调用 `TaskRegistry`

4. `Delivery Adapter`

- 职责：根据已记录的 `deliveryContext` / `threadId` 向原线程发送状态

5. `Recovery`

- 职责：Gateway 启动时扫描未完成任务，重建 watcher 视图并补发中断或恢复状态

## 为什么不用“纯 hook”

`hook` 适合做“强制登记”和“强制收尾”，但不适合承担定时轮询：

- hook 只在事件发生时运行
- hook 本身不会在 5 分钟后自动再次触发
- 如果把每个任务的调度也塞进 hook，会把状态和调度耦合得很散

因此正确方案是：

- hook 或共享入口逻辑负责 `create_task_record`
- watcher 负责之后每 5 分钟轮询与发送

## 为什么不用“一任务一 cron”

不建议为每个任务动态创建一个 cron job，原因如下：

1. job 数量会膨胀，维护成本高。
2. 清理失败时容易遗留脏 job。
3. Gateway 重启后更难统一恢复。
4. 同一线程多个任务的节流和去重会变复杂。

推荐方案：

- 保持一个全局 watcher
- watcher 每分钟或每 5 分钟扫描一次
- 每个任务自己维护 `nextProgressDueAt` 或 `lastProgressAt`

## 状态模型

第一阶段定义以下任务状态：

- `accepted`
  - 已创建任务记录，但实际运行尚未完全开始
- `running`
  - 任务正在执行
- `running-no-output`
  - 任务仍存活，但在设定窗口内无新输出
- `stalled`
  - 任务疑似卡住，需要回报“仍在运行但无进展”
- `completed`
  - 任务正常完成
- `failed`
  - 任务执行失败
- `cancelled`
  - 任务被显式取消
- `interrupted`
  - 任务被 Gateway 重启、进程消失或运行时中断打断

状态迁移规则：

```text
accepted -> running
accepted -> failed
running -> running-no-output
running-no-output -> running
running / running-no-output -> stalled
running / running-no-output / stalled -> completed
running / running-no-output / stalled -> failed
running / running-no-output / stalled -> cancelled
running / running-no-output / stalled -> interrupted
```

## 任务记录结构

建议持久化到：

```text
~/.openclaw/tasks/progress/running/<taskId>.json
~/.openclaw/tasks/progress/completed/<taskId>.json
```

建议字段：

```json
{
  "taskId": "task_20260306_xxx",
  "runtimeKind": "acp",
  "runtimeAgentId": "codex",
  "runtimeSessionKey": "agent:codex:acp:...",
  "runtimeRunId": "optional-run-id",
  "provider": "codex-cli",
  "status": "running",
  "createdAt": "2026-03-06T13:00:00Z",
  "updatedAt": "2026-03-06T13:00:00Z",
  "startedAt": "2026-03-06T13:00:01Z",
  "completedAt": null,
  "lastActivityAt": "2026-03-06T13:00:10Z",
  "lastOutputAt": "2026-03-06T13:00:10Z",
  "lastProgressAt": "2026-03-06T13:00:01Z",
  "nextProgressDueAt": "2026-03-06T13:05:01Z",
  "progressReportsSent": 0,
  "delivery": {
    "channel": "discord",
    "accountId": "default",
    "to": "channel:1234567890",
    "threadId": "1234567890"
  },
  "requesterSessionKey": "agent:main:discord:channel:...",
  "requestText": "让 cc cli 查一下 openclaw 的最新版本反馈",
  "summary": {
    "lastKnownPhase": "spawned",
    "lastKnownMessage": "ACP session created"
  },
  "watchPolicy": {
    "intervalSeconds": 300,
    "stallAfterSeconds": 300,
    "interruptOnGatewayRestart": true
  },
  "debug": {
    "pid": 12345,
    "cliSessionId": "optional",
    "backend": "acpx"
  }
}
```

## 进度消息语义

避免只发送“还在跑”这种低信息量提示，统一分四类：

1. `started`

- 任务已派发
- 说明 runtime 类型与目标
- 说明是否是 thread-bound session

2. `running`

- 已运行多久
- 最近一次活动时间
- 最近一次输出时间

3. `stalled`

- 进程仍存活，但长时间无输出或无状态推进
- 明确写出“未检测到新输出”

4. `interrupted` / `failed`

- 说明中断原因
- 如有可能，附带上一次已知状态

建议文案示例：

- `任务已派发到 ACP codex 会话，后续结果会继续回到当前线程。`
- `任务仍在运行，已持续 10 分钟；最近一次输出是 6 分钟前。`
- `任务仍存活，但 5 分钟内没有检测到新输出，可能卡在 CLI / tool 调用阶段。`
- `任务被网关重启中断，已停止等待；最后已知状态：running-no-output。`

## 接入点设计

### A. ACP 路径

关键文件：

- `src/agents/acp-spawn.ts`

接入策略：

- 在 `spawnAcpDirect()` 返回 `accepted` 前创建任务记录
- 记录 `runtimeKind=acp`
- 写入 `childSessionKey`、`runId`、`agentId`
- 如果线程绑定成功，保存 `delivery.threadId`
- 如果 ACP policy/config 检查失败，则不创建 running 任务，而是直接回报错误

注意：

- ACP 当前没有与 subagent 对等的通用生命周期 hook，因此不应把 ACP 监控逻辑完全寄托在 hook 上。
- ACP 的任务登记应放在共享 spawn 成功路径内。

### B. Subagent 路径

关键文件：

- `src/agents/subagent-spawn.ts`

接入策略：

- 在 `spawnSubagentDirect()` 成功拿到 `childSessionKey` / `runId` 后创建任务记录
- 记录 `runtimeKind=subagent`
- 沿用已有 `subagent_spawning` / `subagent_spawned` / `subagent_ended` hook 做附加通知或清理
- 但任务登记本身不要依赖 hook 是否存在

### C. 本地 CLI backend / fallback 路径

关键文件：

- `src/agents/cli-backends.ts`
- `src/agents/cli-runner.ts`
- 以及实际触发 fallback 的 Gateway / agent 调用路径

接入策略：

- 在真正启动 `claude` / `codex` 进程前创建任务记录
- 记录 `runtimeKind=cli-backend`
- 记录 `provider=claude-cli|codex-cli|custom`
- 如果拿得到 PID，写入 `debug.pid`
- 如果拿得到 CLI session id，也写入 `debug.cliSessionId`

这是必须覆盖的路径，因为当前最容易出现“fallback 已启动，但没有 watcher”的静默失败。

## Watcher 设计

### 方案优先级

优先方案：Gateway 内部常驻 `ProgressWatcherService`

备选方案：单一 cron job 调用 Gateway method 或本地脚本

原因：

- 内部 service 更容易读取运行态上下文
- 不需要额外 shell glue
- 更容易和 restart lifecycle 对齐

如果为了先快速落地，也可以先用单一 cron 版本验证状态机，再收敛回 Gateway 内部 service。

### Watcher 扫描逻辑

每次 tick 对所有 `running` / `running-no-output` / `stalled` 任务执行：

1. 读取任务记录
2. 解析 runtime 类型
3. 获取运行态信息
4. 计算是否需要更新状态
5. 计算是否需要发送进度
6. 原子写回任务记录

### 运行态探测规则

#### ACP

- 优先读 ACP session manager 状态
- 次选检查 `runtimeSessionKey` 是否仍可解析
- 若 session 已关闭且无完成记录，则标记 `interrupted` 或 `failed`

#### Subagent

- 读 subagent registry / active run 信息
- 若 run 不存在但无完成事件，则标记 `interrupted`

#### CLI backend

- 若有 PID，先检查 PID 是否存活
- 若支持 session id，则进一步检查 session 是否仍可 resume / query
- PID 存活但长时间无输出：标记 `running-no-output` 或 `stalled`
- PID 不存在且无 completion：标记 `interrupted`

### 发送节流

- 首次进度：任务启动后满 5 分钟
- 后续进度：每隔 5 分钟最多一次
- 状态变更优先于节流：
  - 进入 `stalled`
  - 进入 `interrupted`
  - 进入 `failed`
  - 进入 `completed`

## 重启恢复设计

### 启动时恢复

Gateway 启动时扫描：

- `~/.openclaw/tasks/progress/running/*.json`

对每个任务执行 reconcile：

1. 如果运行态仍存在

- 恢复为 `running` 或 `running-no-output`
- 若距离上次进度已超过阈值，可补发“已恢复监控”消息

2. 如果运行态不存在

- 标记为 `interrupted`
- 发送中断通知

### 重启时中断语义

若 Gateway 在任务运行时收到 SIGTERM / restart：

- 不要求立即把所有任务判失败
- 但必须确保 watcher 恢复后能给出一致结论

建议语义：

- 在关停前写一个 `gatewayRestartedAt` sentinel
- 启动后恢复任务时，如果任务没有外部独立存活证据，则标记 `interrupted`

## 实施阶段

## Phase 1: 核心持久化与状态机

目标：先建立统一任务存储和状态变更 API。

建议新增文件：

- `src/agents/task-progress/types.ts`
- `src/agents/task-progress/store.ts`
- `src/agents/task-progress/state.ts`
- `src/agents/task-progress/ids.ts`

任务：

1. 定义 `TaskProgressRecord` 类型
2. 实现 `create/update/complete/fail/interrupt/listRunning`
3. 统一 running/completed 目录布局
4. 增加原子写入与 basic validation

验收标准：

- 能创建任务记录
- 能按状态迁移更新
- 能列出 running tasks
- 能把完成任务迁移到 completed

## Phase 2: 统一入口接入

目标：让所有异步 coding 入口都进入任务登记。

优先接入文件：

- `src/agents/acp-spawn.ts`
- `src/agents/subagent-spawn.ts`
- `src/agents/cli-runner.ts`

任务：

1. ACP spawn accepted 时自动建档
2. subagent spawn accepted 时自动建档
3. CLI backend 启动前自动建档
4. spawn 失败路径不落 running 记录

验收标准：

- 三条入口都能稳定生成任务记录
- 失败路径不会留下脏 running 记录

## Phase 3: Watcher 服务

目标：实现单一 watcher 的扫描和回报。

建议新增文件：

- `src/agents/task-progress/watcher.ts`
- `src/agents/task-progress/runtime-probes.ts`
- `src/agents/task-progress/delivery.ts`

任务：

1. 实现 watcher tick
2. 实现 ACP / subagent / CLI runtime probe
3. 实现统一文案生成
4. 实现 5 分钟节流

验收标准：

- 运行超过 5 分钟的任务能自动回报
- 无输出任务能被识别为 `running-no-output` 或 `stalled`
- 完成或失败后停止继续回报

## Phase 4: Gateway 生命周期集成

目标：把 watcher 挂到 Gateway 生命周期，并实现重启恢复。

候选接入文件：

- `src/gateway/server-startup.ts`
- `src/gateway/server.impl.ts`
- `src/cli/gateway-cli/run-loop.ts`

任务：

1. Gateway 启动时启动 watcher
2. Gateway 启动时恢复 running tasks
3. Gateway restart 时写 sentinel 或中断标记
4. Gateway 停止时优雅关闭 watcher

验收标准：

- 重启后 watcher 自动恢复
- 中断任务能收到显式状态

## Phase 5: Hook 集成与策略开关

目标：让这套机制具备“强制执行”的控制面。

建议新增：

- 配置项：`agents.defaults.asyncTaskProgress.*`
- 可选 hook：用于补充策略，而不是承担调度

建议配置：

```json5
{
  agents: {
    defaults: {
      asyncTaskProgress: {
        enabled: true,
        intervalSeconds: 300,
        stallAfterSeconds: 300,
        notifyOnStart: true,
        notifyOnInterrupt: true,
        notifyOnCompletion: true,
      },
    },
  },
}
```

任务：

1. 增加配置 schema
2. 根据配置启停 watcher
3. 允许按 agent 或 runtime 覆盖策略

验收标准：

- 可以统一开启或关闭该能力
- 默认开启后，异步任务自动进入监控

## 测试计划

### 单元测试

- 任务记录创建、更新、完成、失败、恢复
- 状态迁移合法性
- 节流逻辑
- 进度文案生成

### 集成测试

- ACP accepted -> running -> completed
- subagent accepted -> stalled -> completed
- CLI backend accepted -> running-no-output -> interrupted
- Gateway restart -> 恢复 running tasks -> 补发中断或恢复状态

### 回归测试

- 未启用 watcher 时，不影响原有异步执行
- ACP policy disabled 时，错误仍保持清晰
- Discord thread binding disabled 时，错误仍保持清晰

## 风险与应对

### 风险 1：状态源不一致

ACP、subagent、CLI backend 三类运行时的“活跃”定义不同。

应对：

- 把 runtime probe 封装成每类一个适配器
- watcher 不直接依赖单一字段判断

### 风险 2：重复发送进度

重启恢复或并发 tick 容易导致重复消息。

应对：

- 持久化 `lastProgressAt`
- 发送前再次 compare-and-write

### 风险 3：把慢任务误判成卡死

有些 CLI 本来就长时间无输出。

应对：

- 第一阶段只标记 `running-no-output` / `stalled`
- 不自动 kill

### 风险 4：覆盖路径不完整

如果只接 ACP/subagent，不接本地 CLI fallback，用户仍会遇到静默。

应对：

- Phase 2 明确把 `cli-runner` 纳入必做项

## 最小可用版本

如果要先快速交付一个可用版本，建议裁剪为：

1. `TaskRegistry`
2. `src/agents/acp-spawn.ts` 接入
3. `src/agents/subagent-spawn.ts` 接入
4. `src/agents/cli-runner.ts` 接入
5. 单一 watcher
6. Discord delivery only

第一版先不做：

- 多渠道细粒度文案定制
- UI 面板展示
- 任务强制取消
- 复杂恢复重试

## 推荐执行顺序

1. 先实现 `TaskRegistry`
2. 接入三条异步入口
3. 实现 watcher + delivery
4. 接入 Gateway 启动/重启恢复
5. 最后补配置项和策略开关

## 交付定义

满足以下条件即可视为本计划完成：

1. 从 Discord 派发一个异步 coding 任务后，原线程会立即收到“已派发”反馈。
2. 任务运行超过 5 分钟仍未结束时，原线程会自动收到进度回报。
3. 任务正常完成、失败或中断时，原线程会收到最终状态。
4. Gateway 重启后，不会再出现“任务还在跑，但 5 分钟 watcher 丢失”的静默故障。
