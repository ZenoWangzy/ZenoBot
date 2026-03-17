# OpenClaw `sessions_send` 完成通知可靠性方案决策（A/B/C）

> 任务目标：在“继续已有会话执行任务”场景下，确保最终 completion 通知可靠送达（尤其是等待超时后仍能回调）。

## 0. 方法说明（含 Claude Code CLI）

- 已使用 Claude Code CLI 发起评估分析请求（`claude -p ...`）。
- 本机该次 CLI 调用长时间无输出并挂起，按约束切换为仓库直接分析并给出最终决策。
- 分析依据文件：`cc-hook-notify-optimization.md`（含根因、三方案描述与实现线索）。

---

## 1. 加权评估模型（建议权重）

为“当前可落地且显著降低丢通知”目标，建议权重如下（总计 100）：

- **可靠性 35**：本问题的主目标，权重最高。
- **实现复杂度 15**：复杂度越高，出错面越大、交付不确定性越高。
- **向后兼容 15**：线上已有调用方较多，协议兼容很关键。
- **可观测性 10**：需要定位“通知为何没到/是否重复”。
- **运维风险 15**：包括重启恢复、异常重试、重复发送等生产风险。
- **交付时间 10**：短期需要止血，不能只追求理想架构。

> 评分标准：1~5 分（5 分最好）。复杂度/风险/时间维度按“越容易、越低风险、越快交付分数越高”。

---

## 2. 三方案评分与结论

## 2.1 汇总表

- **A) Correlation ID / Task Envelope**
  - 可靠性 5
  - 实现复杂度 4
  - 向后兼容 5
  - 可观测性 4
  - 运维风险 4
  - 交付时间 4
  - **加权总分：4.50 / 5（90/100）**

- **B) Completion watcher / event bus**
  - 可靠性 5
  - 实现复杂度 2
  - 向后兼容 4
  - 可观测性 5
  - 运维风险 3
  - 交付时间 2
  - **加权总分：3.80 / 5（76/100）**

- **C) Parent-child run attachment retrofit**
  - 可靠性 4
  - 实现复杂度 3
  - 向后兼容 3
  - 可观测性 3
  - 运维风险 3
  - 交付时间 3
  - **加权总分：3.40 / 5（68/100）**

## 2.2 评分解释（简要）

- **A 高分原因**：直接补齐 `sessions_send` 的“durable tracking + 可恢复回调”缺口，改动范围可控，且能复用现有 announce/idempotency 机制。
- **B 的问题**：长期架构最优潜力高，但短期改造面大（事件总线持久化、订阅模型、投递语义），不是“现在最快止血”路径。
- **C 的问题**：复用性有吸引力，但语义上 `send` 并非 `spawn` 子任务，强行父子挂接会带来模型混淆与后续维护负担。

---

## 3. 架构取舍与失败处理

## 3.1 关键取舍

- **A（推荐）取舍**：
  - 优点：最小化 API 破坏，快速把“超时即丢通知”改为“超时仅影响本次等待，不影响最终回调”。
  - 代价：需要新增/扩展 continuation registry 与状态机。

- **B 取舍**：
  - 优点：平台化、统一事件驱动，未来扩展性最好。
  - 代价：引入系统级基础设施，短期风险和时间成本都高。

- **C 取舍**：
  - 优点：复用现有 `subagent` 链路。
  - 代价：语义错位（send≠spawn）导致权限、展示、清理策略复杂化。

## 3.2 失败场景处理（推荐以 A 落地）

1. **timeout（最关键）**
   - 现状风险：`agent.wait` timeout 后直接返回，不再追踪。
   - A 处理：提交 run 后立即持久化 continuation；timeout 只影响本次 RPC 返回，后台 watcher 继续等待并补发 completion。

2. **agent/gateway 重启**
   - A 处理：启动恢复逻辑扫描 `pending/running` continuation，重新接管 wait + announce。

3. **重复 completion（重复事件/重复恢复）**
   - A 处理：状态机 CAS（`completed -> announced` 原子推进）+ 幂等发送键，确保“最多一条最终态通知”。

4. **partial output（部分输出/尚未 final）**
   - A 处理：仅在 run 终态触发最终通知；若仅有中间输出可选发“仍在执行”进度提示，不发 final completion。

---

## 4. 最终推荐（只选一个）

## ✅ 选择 **A) Correlation ID / Task Envelope**

**为什么是当前 OpenClaw 架构下“现在最优”**：

1. **直击根因**：把 `sessions_send` 从进程内 best-effort 回调升级为可恢复的 durable 跟踪，直接消除 timeout 后漏通知主因。
2. **改造半径最小**：不需要先建设完整事件总线；可复用已有 subagent announce 经验与幂等策略。
3. **兼容性高**：新增字段均可选，旧调用方可无感升级。
4. **可渐进演进**：后续可平滑演进到 B（事件总线），A 不会成为无用重构。

---

## 5. 分阶段上线计划（P0/P1/P2）

## P0（止血版，1~2 个迭代）

- 引入 continuation record（持久化）：`continuationId`, `runId`, `requesterOrigin`, `notifyTarget`, `status`, `retryCount`。
- `sessions_send` 在 run 创建成功后立即登记。
- timeout/error 分支不丢弃后续通知。
- 引入 feature flag：`sessionsSendDurableNotify`（默认关，便于灰度）。

## P1（灰度稳态）

- 灰度到 Discord 指定会话/频道。
- 补齐观测指标：
  - completion 丢失率
  - 重复通知率
  - 完成通知延迟 P50/P95
  - giveup 比例
- 完成恢复演练（进程重启、网络闪断）。

## P2（默认开启 + 收敛）

- 默认启用 durable notify。
- 保留 `notifyOnCompletion:false` 作为逃生阀。
- 收敛旧 ephemeral flow 为兼容 fallback，并明确退场路径。

---

## 6. 验收测试（Acceptance Tests）

1. **超时后补发**
   - 输入：`sessions_send(timeout=1s)`，实际任务 10s 完成。
   - 期望：先返回 timeout；随后 Discord 收到一次 final completion。

2. **重启恢复**
   - 输入：run 提交后立即重启 gateway/agent。
   - 期望：恢复后仍能送达 final completion，无人工干预。

3. **去重**
   - 输入：模拟重复 lifecycle end 事件 / watcher 重放。
   - 期望：最终态消息只出现 1 次。

4. **部分输出不误终态**
   - 输入：任务产生中间输出但未结束。
   - 期望：不发送 final completion；仅可选进度提示。

5. **目标路由优先级**
   - 输入：同时存在显式 `notifyTarget` 与推断目标。
   - 期望：显式目标优先；缺失时回退 requesterOrigin，再回退推断。

---

## 7. 回滚方案

- 一键关闭 `sessionsSendDurableNotify`，回退到旧路径（ephemeral announce）。
- 保留新 registry 读能力但停写（避免直接删除数据结构）。
- 回滚观察窗口内重点监控：重复通知、通知延迟、超时后丢失率。

---

## 8. API / 协议增量与语义

## 8.1 `sessions_send` 请求新增（可选）

- `notifyOnCompletion?: boolean`（默认 `true`）
  - `true`：纳入 durable tracking。
  - `false`：仅当前轻量行为（不保证离线补发）。
- `continuationId?: string`（客户端可传；不传服务端生成）
- `notifyTarget?: { channel: string; to: string; accountId?: string; threadId?: string }`
- `notifyMode?: "announce" | "silent"`（默认 `announce`）

## 8.2 `sessions_send` 返回新增

- `continuationId: string`
- `tracking: { durable: boolean; status: "accepted" | "watching" | "disabled" }`
- 若本次 wait 超时：`status: "timeout"` + `tracking.durable=true`（表示后台仍会追踪并补发）

## 8.3 语义约束

- timeout ≠ task failed。
- “最终态通知”以 continuation 状态机为准，而非单次工具调用生命周期。

---

## 9. 幂等模型

- **幂等主键建议**：`idempotencyKey = sha256(continuationId + runId + finalState)`
- **状态机**：`pending -> running -> completed -> announced | giveup`
- **并发控制**：状态迁移采用 CAS/事务写；只有首个成功迁移到 `announced` 的 worker 才可发送。
- **重试策略**：指数退避 + 最大重试次数 + 过期时间（expiry）。

---

## 10. Discord 用户可见变化（优化后）

用户在 Discord 中应感知到：

1. **超时文案更准确**：
   - “本次等待超时，任务仍在后台继续。完成后会自动通知你。”
2. **最终结果可达**：
   - 即使中途超时或服务重启，也能收到最终 completion。
3. **减少重复消息**：
   - 同一 continuation 最终态只到达一次。
4. **失败可解释**：
   - 若最终失败，收到一条明确失败通知（含最小必要错误上下文）。

---

## 最终决策

在当前 OpenClaw 架构与交付约束下，**选择 A（Correlation ID / Task Envelope）** 作为首选方案。它在可靠性、兼容性、实施速度之间达到最佳平衡，并可作为未来演进到事件总线方案（B）的稳健台阶。
