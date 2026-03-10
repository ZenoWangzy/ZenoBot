# OpenClaw 并发 continuation 能力评估（同一会话上下文）

时间：2026-02-23 23:33 GMT+8  
范围：基于当前代码与现有架构（`sessions_send` / `sessions-send-tool.a2a.ts` / `subagent-registry*.ts`）

---

## 结论（必须项）

**1) 当前是否已充分支持多进程/多线程并发安全？**

## 结论：**No**（不是 Partial，是 No）

原因：

- 当前 `sessions_send` 主路径仍是进程内 `void runSessionsSendA2AFlow(...)` 异步 flow（best-effort）。
- 没有可见的 continuation durable registry、无跨进程 owner/lease、无原子状态迁移 CAS。
- 状态持久化（参考 subagent registry）是 JSON 文件读写，未见文件锁/事务日志/租约机制，不满足多实例并发写一致性要求。

---

## 2) 并发冲突面清单

## A. 同 `continuationId` 重入（高）

- 现状：`sessions_send` 尚未形成强约束 continuation 状态机（至少在当前可见代码中无）。
- 风险：重试/重复请求可能创建多 watcher 或多次 announce。

## B. 不同 `continuationId` 竞争同 `runId`（高）

- 现状：缺少“runId 唯一归属”检查。
- 风险：同一 run 可能被多个 continuation 绑定，导致重复完成通知或状态撕裂。

## C. 重复 announce（高）

- 现状：`sessions-send-tool.a2a.ts` 发送 `send` 时用 `crypto.randomUUID()` 作为 idempotencyKey（每次不同）。
- 风险：重放/恢复/双进程同时执行时，网关端无法按稳定键去重。

## D. 重启恢复竞争（高）

- 现状：`sessions_send` 不具备类似 subagent 的统一恢复注册表。
- 风险：进程 A 超时返回后退出；进程 B 无法接力 watcher，或两个进程都尝试补发。

## E. 跨实例并发写状态文件（高）

- 现状：参考 `subagent-registry.store.ts`：`saveJsonFile` 全量写，无文件锁/版本 compare-and-swap。
- 风险：最后写入覆盖（lost update）、脏写、状态回退。

## F. 多线程/事件循环内并发推进同状态（中）

- 现状：内存 Map 级别有 `cleanupHandled` 这类软防重（subagent 路径），但非事务语义。
- 风险：同进程高并发下仍可能出现 TOCTOU 窗口。

---

## 3) 已覆盖 vs 未覆盖（按风险高→低）

## 未覆盖（高风险）

1. **sessions_send 的 durable continuation 跟踪缺失**（根因级）。
2. **跨实例唯一 owner/lease 缺失**（谁负责 watch/run->announce 不确定）。
3. **稳定幂等键缺失**（announce 难以全局去重）。
4. **状态存储无原子迁移/无锁写**（多实例文件写冲突）。
5. **runId 与 continuationId 双向唯一约束缺失**。

## 已覆盖（相对低风险，且主要在 subagent 路径）

1. `subagent-registry` 有持久化 + 重启恢复 + retry 上限 +过期保护。
2. `cleanupHandled/cleanupCompletedAt` 对单进程内重复清理有一定抑制。
3. `onAgentEvent + agent.wait` 双通道监听提升了完成捕获概率（subagent 专用）。

> 注意：这些“已覆盖”并不能等价迁移到 `sessions_send`，因此总体结论仍是 **No**。

---

## 4) 最小增强方案（P1）——让多进程/多实例可靠起来

目标：最小改造实现“至少一次完成捕获 + 最多一次最终通知（可观测）”。

## P1.1 durable continuation registry（必须）

新增记录：

- `continuationId`（全局主键）
- `runId`（唯一映射）
- `requesterSessionKey/requesterOrigin/notifyTarget`
- `status`: `pending|watching|completed|announced|giveup`
- `version`（单调递增，用于 CAS）
- `ownerId`、`leaseUntil`（watch owner 机制）
- `announceKey`（稳定幂等键）

约束：

- 唯一：`continuationId` 唯一；`runId` 只允许绑定一个 active continuation。

## P1.2 锁/租约机制（必须）

- 采用文件锁（如 flock）或外部 KV（更优）实现 lease。
- 只有持有 lease 的 owner 才能推进 `watching->completed->announced`。
- lease 超时可被其他实例抢占，防 owner 崩溃悬挂。

## P1.3 原子状态迁移（必须）

- CAS 条件更新：`where continuationId=? and version=?`（文件方案可用 journal+版本校验模拟）。
- 防止双 worker 同时从 `completed` 推进到 `announced`。

## P1.4 幂等键策略（必须）

- `announceIdempotencyKey = sha256(continuationId + runId + finalState)`
- 不再使用随机 UUID 作为最终通知键。
- 下游 `send` 遇重复键返回已处理视作成功。

## P1.5 兼容策略（建议）

- 默认开启 durable，但保留 `notifyOnCompletion=false` 作为逃生阀。
- 对旧调用方自动生成 continuationId，返回 tracking 元数据。

---

## 5) 并发测试设计（可执行级别，>=6 条）

以下用例建议在 CI 增加“双 worker/双进程”测试组（可通过 fork 子进程或启动两个网关实例模拟）：

1. **同 continuationId 并发重入**

- 步骤：两个进程同时提交同 continuationId。
- 断言：只创建一条 active 记录；第二次返回已存在/幂等接受；最终仅 1 条 announce。

2. **不同 continuationId 绑定同 runId 竞争**

- 步骤：并发写入 c1->runX、c2->runX。
- 断言：仅一个成功，另一个冲突失败；最终仅一次 completion 通知。

3. **双进程同时 watcher 抢占**

- 步骤：A、B 同时扫描 pending；A 获得 lease，B 失败。
- 断言：仅 owner 推进状态并发送；B 不发送。

4. **owner 崩溃后接管**

- 步骤：A 获 lease 后 kill -9；等待 lease 过期，B 接管。
- 断言：B 能完成 `completed->announced`；无重复通知。

5. **重复完成事件重放**

- 步骤：对同 run 注入多次 lifecycle end/agent.wait ok。
- 断言：状态仅推进一次，announce 只发一条（基于稳定幂等键）。

6. **跨实例并发写恢复文件**

- 步骤：两个实例高频更新 registry（含重启恢复场景）。
- 断言：无 JSON 损坏、无状态回退（version 单调）、无丢记录。

7. **timeout 先返回 + 后续完成补发**（补充关键业务用例）

- 步骤：调用 timeout=1s，任务 10s 完成；期间重启一个实例。
- 断言：调用方先收到 timeout；最终仍收到 completion，且仅 1 次。

---

## 风险分级汇总

- **高风险**：同 run 多 continuation、重复 announce、重启恢复竞争、跨实例状态写冲突。
- **中风险**：同进程事件竞争（TOCTOU）导致重复推进。
- **低风险**：单进程、低并发、无重启场景下的偶发重复/漏发（相对可控但仍存在）。

---

## 一句话结论

当前实现对“异步多进程/多实例并发 continuation”**尚未充分支持（No）**；需在 P1 补齐 **lease + CAS + 稳定幂等键 + run/continuation 唯一约束** 才能达到可生产级并发可靠性。
