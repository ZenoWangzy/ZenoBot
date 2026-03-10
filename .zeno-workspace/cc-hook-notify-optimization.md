# OpenClaw 子会话继续执行（`sessions_send`）完成通知可靠性优化设计报告

> 结论先行：当前 `sessions_spawn` 之所以通知可靠，核心是**有持久化 run 注册表 + 生命周期监听 + 恢复重试**；而 `sessions_send` 的完成通知主要依赖工具调用进程内的**临时异步 flow（best-effort）**，且在 `agent.wait` 超时分支不启动后续 announce flow，导致“旧会话继续跑完但主会话/网关未收到 completion 回调”的概率显著上升。

---

## 0. 调研说明（含 Claude CLI）

- 已尝试使用 Claude Code CLI 对目标文件做统一分析，但 CLI 进程在本机被 SIGKILL（挂起/超时）中断。
- 按约束要求，已切换为直接仓库源码分析并完成本报告。
- 关键代码路径（OpenClaw）：
  - `src/agents/subagent-spawn.ts`
  - `src/agents/subagent-registry.ts`
  - `src/agents/subagent-registry.store.ts`
  - `src/agents/subagent-announce.ts`
  - `src/agents/tools/sessions-send-tool.ts`
  - `src/agents/tools/sessions-send-tool.a2a.ts`
  - `src/gateway/server-methods/agent-job.ts`
  - `src/infra/agent-events.ts`

---

## 1) Root-cause 模型：`sessions_spawn` vs `sessions_send` 回调生命周期

## 1.1 `sessions_spawn`（可靠路径）的生命周期

**路径概览**

1. `sessions_spawn` → `spawnSubagentDirect()` 启动子任务（`method: "agent"`，`deliver:false`）。
2. 调用 `registerSubagentRun()` 将 `{runId, childSessionKey, requesterSessionKey, requesterOrigin, ...}` 写入内存 + 磁盘（`subagent-registry.store.ts`）。
3. 注册表通过两条链路等完成：
   - `onAgentEvent(lifecycle)` 监听 `end/error`；
   - 并行 `agent.wait(runId)` 兜底（跨进程/重启可恢复）。
4. 完成后进入 `runSubagentAnnounceFlow()`：
   - 从 child session 拉取结果；
   - 生成系统触发消息并注入 requester session（或直接外发）；
   - 带 announce idempotency key，避免重复发送。
5. 失败/延迟会记 retry 计数与过期策略（`MAX_ANNOUNCE_RETRY_COUNT`, `ANNOUNCE_EXPIRY_MS`），重启后可恢复。

**可靠性关键点**

- 有**持久化状态机**（run registry）。
- 有**恢复能力**（进程重启后 `restoreSubagentRunsOnce()` 会继续等待并补发）。
- 有**幂等键与重试上限**，防重复且防无限循环。

---

## 1.2 `sessions_send`（旧会话继续）当前生命周期

**路径概览**

1. `sessions_send` 向目标会话发 `agent`（`deliver:false`），得到 `runId`。
2. 若 `timeoutSeconds>0`，同步执行 `agent.wait(runId, timeoutMs)`。
3. 仅当 wait 成功（非 timeout/error）后：
   - 读取历史 reply；
   - 触发 `startA2AFlow()`（`void runSessionsSendA2AFlow(...)` 异步，不受持久化托管）。
4. `runSessionsSendA2AFlow()` 内部再做 announce step，并 best-effort `send` 到 announceTarget。

**关键脆弱点**

- **脆弱点 A：timeout 直接返回，不启动后续 flow**
  - `sessions-send-tool.ts` 中：`waitStatus === "timeout"` 时直接返回 `status:"timeout"`；
  - 该分支没有 `startA2AFlow(...)`，导致 run 后续即便完成，也没人再补发通知。
- **脆弱点 B：无持久化任务登记**
  - `sessions_send` 没有像 `sessions_spawn` 那样将“待通知任务”写 registry。
  - 进程重启/工具调用上下文结束后，临时 Promise 消失，无恢复点。
- **脆弱点 C：announce 依赖会话推断目标（弱关联）**
  - `resolveAnnounceTarget()` 从 session key / sessions.list 推导 channel/to；
  - 对“旧会话 + 多渠道切换 + requester 已迁移”场景，目标可能陈旧或缺失。
- **脆弱点 D：A2A flow 是 best-effort fire-and-forget**
  - `void runSessionsSendA2AFlow(...)` 无统一调度器托管，无重试持久化。

---

## 1.3 “通知在哪被发出/在哪丢失”模型

- 发出点：
  - spawn：`runSubagentAnnounceFlow()`（registry 驱动）
  - send：`runSessionsSendA2AFlow()`（临时异步）
- 丢失点（send 路径高发）：
  1. `agent.wait` 超时分支提前 return（最关键）。
  2. wait 成功前/后进程重启，临时 flow 丢失。
  3. announce target 推断失败或过时。
  4. announce step 内部失败仅 warn，不会持久化重试。

---

## 2) 设计选项（2~3 个）

## 选项 A：Correlation ID / Task Envelope（推荐）

### 核心思想

把 `sessions_send` 的“继续任务”也提升为可追踪的**逻辑任务（Continuation Task）**，与 `runId` 解耦：

- 创建 `continuationId`（或 `taskId`），封装 requester/target/origin/通知策略。
- 提交后立即持久化到 registry（可复用 subagent registry，或新建 continuation registry）。
- 后台 watcher 按 `runId` 等待完成，再执行统一 announce flow。
- 即使调用方超时返回，也不会丢任务。

### 协议字段建议

在 `sessions_send` 入参新增可选（向后兼容）：

- `notifyOnCompletion?: boolean`（默认 `true`，旧行为维持）
- `continuationId?: string`（客户端可传，不传则服务端生成）
- `notifyTarget?: { channel,to,accountId?,threadId? }`（可选显式覆盖）
- `notifyMode?: "announce" | "silent"`（默认 announce）

返回补充：

- `continuationId`
- `tracking: { durable: true, status: "accepted" | "watching" }`

### 优点

- 最小破坏现有语义；
- timeout 不再等于丢通知；
- 可复用已有 announce/idempotency 机制；
- 便于跨重启恢复。

### 代价

- 需要新增 registry 类型或扩展现有 schema。

---

## 选项 B：Completion Watcher / Event Bus

### 核心思想

引入统一“完成事件总线”：

- 任意 `agent` run 完成时发布 `run.completed`；
- `sessions_send` 只需在发送时注册订阅规则（runId→notify action）；
- watcher 进程消费事件并执行通知。

### 优点

- 架构清晰、可扩展到 cron/外部任务等；
- 解耦工具层与通知层。

### 代价

- 系统级改造较大；
- 需保障事件持久化与至少一次投递。

---

## 选项 C：Parent-Child Run Attachment Retrofit

### 核心思想

把 `sessions_send` 发起的 run retrofitted 成“附着任务”：

- 记录 `parentRunId` 或 `parentSessionKey` + `spawnedByLike` 字段；
- 让现有 subagent registry 把这类 run 当作“可 announce 子任务”处理。

### 优点

- 最大化复用 subagent 完成处理链。

### 代价

- 语义上 `send` ≠ `spawn`，硬挂父子关系易混淆；
- 需要谨慎区分清理/展示/权限逻辑。

---

## 3) 推荐方案

**推荐：A（Task Envelope + Correlation ID）**，并借鉴 C 的“复用现有 announce 执行器”。

### 为什么推荐 A

- 能直击当前故障根因（timeout 分支不追踪 + 无持久化）。
- API 变化小，默认行为可保持。
- 兼容未来向 B（事件总线）演进。

### 最小 API 变更

1. `sessions_send` 请求新增可选字段：
   - `notifyOnCompletion?: boolean = true`
   - `continuationId?: string`
   - `notifyTarget?: DeliveryContext`
2. `sessions_send` 返回新增：
   - `continuationId`（服务端最终确认值）
   - `delivery.tracking = "durable" | "ephemeral"`

### 处理语义

- 当 `notifyOnCompletion=true`：
  - 无论 `agent.wait` 结果是 `ok/timeout/error`，都登记 durable watcher；
  - timeout 仅影响本次 tool 调用返回，不影响后续完成通知。
- 当 `notifyOnCompletion=false`：
  - 保持当前轻量行为（可不追踪）。

---

## 4) 向后兼容与迁移计划

## 4.1 向后兼容

- 老调用方不传新字段：默认等价于 `notifyOnCompletion=true`（建议）或按配置开关灰度。
- 旧返回字段不删除，只追加新字段。
- `sessions_spawn` 逻辑不变。

## 4.2 迁移阶段

1. **Phase 0（隐藏开关）**：
   - `agents.defaults.sessionsSend.durableNotify=false`（默认关）
2. **Phase 1（灰度）**：
   - 部分 agent/channel 打开 durable notify；
   - 监控重复通知率、延迟、丢失率。
3. **Phase 2（默认开启）**：
   - durable notify 默认 true；
   - 保留 `notifyOnCompletion:false` 逃生阀。
4. **Phase 3（清理）**：
   - 将旧 ephemeral announce flow 仅保留作兼容 fallback。

---

## 5) Failure-mode 矩阵 + 幂等策略

| 失败模式               | 当前 send 风险         | 推荐方案行为                                          | 幂等策略                                                   |
| ---------------------- | ---------------------- | ----------------------------------------------------- | ---------------------------------------------------------- |
| `agent.wait` timeout   | 高：直接返回且不再追踪 | 记录 watcher，run 完成后补发                          | `announceId = continuationId + runId`，固定 idempotencyKey |
| Agent/Gateway 重启     | 高：临时 Promise 丢失  | registry 恢复后继续 wait+announce                     | registry 持久化 + 去重键                                   |
| 重复完成事件           | 中：可能重复发         | 消费端去重，状态机 CAS（pending→announced）           | 幂等写 + 发送去重缓存                                      |
| 部分输出（run 仍活跃） | 中：可能提前发         | 检测 run active，延迟宣布                             | 重试窗口 + 过期保护                                        |
| announce 目标失效      | 中                     | 优先显式 notifyTarget，其次 requesterOrigin，最后推断 | 目标版本戳/最后校验                                        |
| announce 调用失败      | 中                     | 按退避重试至上限                                      | retryCount + expiry + 幂等 send                            |

**状态机建议（continuation registry）**

- `pending` → `running` → `completed` → `announced` / `giveup`
- 更新必须原子 compare-and-set，防并发重复通知。

---

## 6) 具体实现计划（模块/文件、测试、发布）

## 6.1 可能改动模块（路径级）

1. `src/agents/tools/sessions-send-tool.ts`
   - 解析新字段。
   - 在 `agent` 提交成功后注册 continuation record。
   - timeout/error 分支不再意味着“放弃后续通知”。

2. 新增（建议）`src/agents/sessions-send-registry.ts`
   - 维护 continuation 记录、状态机、重试计数。
   - 启动恢复逻辑（类似 `subagent-registry.ts`）。

3. 新增（建议）`src/agents/sessions-send-registry.store.ts`
   - 磁盘持久化，版本化 schema。

4. `src/agents/tools/sessions-send-tool.a2a.ts`
   - 将 announce 执行抽离为可复用函数（由 registry 调度调用）。
   - 保留现有即时路径作为快速反馈。

5. 可复用：`src/agents/subagent-announce.ts`
   - 抽公用 announce 发送与 idempotency 逻辑（避免双实现）。

6. `src/gateway/server-methods/agent-job.ts`
   - 现有 `agent.wait` 可继续复用；必要时补充查询接口（可选）。

## 6.2 测试计划

### 单元测试

- timeout 分支仍能触发后续完成 announce。
- 重启恢复：从 store 恢复 pending continuation 并补发。
- 重复事件/重复恢复不会重复发消息。
- notifyTarget 优先级（显式 > requesterOrigin > 推断）。

### 集成/E2E

1. `sessions_send(timeout=1s)`，实际 run 5s 完成：
   - 调用方先收到 timeout；
   - Discord 最终仍收到 completion。
2. 提交后立刻重启 gateway：
   - run 完成后仍能 announce。
3. 同一 run 多次 lifecycle/end 事件：
   - 仅一条最终消息。
4. 部分输出 + compaction 重试：
   - 不提前发“空结果”。

### 回归

- `sessions_spawn` 现有 announce 行为不退化。
- `subagents steer/kill` 与 suppression 逻辑不受影响。

## 6.3 Rollout 步骤

1. 引入 registry 与 feature flag，默认关闭。
2. 小流量灰度（仅 Discord 主会话）。
3. 观察指标：
   - completion 丢失率
   - 重复通知率
   - 平均通知延迟
   - giveup 比例
4. 放量并默认开启。

---

## 7) 产品行为规范（Discord 侧可见）

## 7.1 `sessions_spawn`

- 用户触发后立即看到“已接受/处理中”（可选）。
- 子任务完成时，总能在原请求上下文收到结果（即使中间超时或网关重启，最多延迟）。
- 不应出现重复 completion 消息（除非明确重试提示）。

## 7.2 `sessions_send` 继续旧会话

- 若超时：
  - 用户先看到“本次等待超时，任务仍在后台继续”。
- 后续完成：
  - 系统自动补发最终结果到同一 Discord 对话线程/频道。
- 若最终失败：
  - 发送一条失败通知（包含最小必要错误信息）。
- 同一 continuation 只发一次最终态（ok/error/timeout-final），可附 run/continuation 引用用于审计。

---

## 附：关键根因一句话

`sessions_spawn` 是“**持久化可恢复任务**”，`sessions_send` 目前是“**进程内临时回调**”；当 `sessions_send` 发生 wait 超时或上下文中断时，缺少 durable tracking，因此 completion 回调会掉。
