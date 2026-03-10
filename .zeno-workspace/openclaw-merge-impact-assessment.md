# OpenClaw 合并影响增量评估（目标：v2026.2.21，只读）

评估时间：2026-02-23 13:21 GMT+8  
仓库：`/Users/ZenoWang/.openclaw/workspace/openclaw`  
评估方式：仅基于本地已 fetch 的 git 历史做只读分析（未做 merge/cherry-pick/rebase）

---

## 执行摘要（决策者版）

1. **影响等级：高（High）**。从当前本地基线 `b251533e` 到 `v2026.2.21` 有 **933 个提交**，跨度大。
2. 触达核心模块非常广：`src/agents`、`src/infra`、`src/gateway`、`src/auto-reply`、`src/config`、`src/discord`、`src/telegram`、`src/cron`。
3. 除“同文件冲突”外，更大的风险是**行为语义变化**（安全收紧、路由规则变化、默认值变化）。
4. 你本地 `main` 工作树干净且不领先 upstream（文本冲突概率低），但**运行时回归概率中高**。
5. 高风险点集中在：Telegram streaming、thread-aware model override、exec/sandbox 安全门控、subagent announce/路由、gateway auth/proxy。
6. 单次直接合并到生产分支不建议。
7. **现在就合并建议：No**（不是不能合，而是不能“一步到位”合）。
8. 若必须合，建议最多 4 批：先安全补丁，再渠道/路由，再执行语义，再 UI/扩展。
9. 每批都要做最小回归（消息发送、会话路由、工具执行、权限拦截、cron 触发）。
10. 结论：可以推进，但必须按“分批 + 护栏 + 验证门禁”。

---

## 1) 影响等级：高（High）及依据

### 结论

**高（High）**

### 依据

1. **提交跨度大**：`b251533e..v2026.2.21 = 933 commits`。
2. **核心模块触达面广**（按目录触达计数，非唯一文件）：
   - `src/agents` 275
   - `src/infra` 130
   - `src/gateway` 128
   - `src/auto-reply` 110
   - `src/cli` 89
   - `src/config` 72
   - `src/discord` 62
   - `src/telegram` 36
   - `src/cron` 27
3. **配置/语义变化明显**：
   - 安全策略明显收紧（allowlist、auth、trusted proxy、heredoc/exec 防护）。
   - 渠道路由与线程模型有新行为（Discord thread-bound subagents、thread-aware model overrides）。
   - Telegram 流式预览/流模式逻辑有多轮修复，行为边界变化概率高。

---

## 2) 最可能冲突 Top 10 文件/目录（按概率）

> 注：这里“冲突”包含三类：
>
> - A. 同文件修改冲突（若你本地有定制补丁）
> - B. 行为语义冲突（文本可自动合但运行结果变）
> - C. 配置兼容冲突（旧配置与新校验/默认值不兼容）

1. **`src/agents/`**

- 概率：极高
- 类型：B + C（部分 A）
- 原因：subagent、tool 调度、嵌入式 runner、announce 链路频繁改动。

2. **`src/gateway/`**

- 概率：极高
- 类型：B + C
- 原因：auth、ws/http 边界、trusted proxy、control-ui 协议与校验都在变化。

3. **`src/infra/exec-approvals-allowlist.ts` 及 `src/infra/*exec*`**

- 概率：高
- 类型：B + C
- 原因：执行授权、allowlist 解析、安全门控持续收紧。

4. **`src/config/`（特别是 schema/help/labels/providers）**

- 概率：高
- 类型：C（兼容）+ B
- 原因：配置字段/提示/provider 解析与默认值不断演进。

5. **`src/auto-reply/reply/commands-subagents.ts`**

- 概率：高
- 类型：B
- 原因：subagent 触发与回复链逻辑变化，对现有自动回复行为影响大。

6. **`src/discord/monitor/*` + `src/channels/*`**

- 概率：中高
- 类型：B + C
- 原因：线程、ephemeral、stream preview、模型覆盖策略等行为变化。

7. **`src/telegram/*`**

- 概率：中高
- 类型：B
- 原因：streaming preview/多段流处理有修复，易触发“看起来能跑但输出异常”。

8. **`src/cron/` + `src/gateway/server-methods/cron.ts`**

- 概率：中高
- 类型：B + C
- 原因：并发、run marker、target 校验、run-log 路径约束发生变更。

9. **`src/gateway/server/ws-connection/message-handler.ts`**

- 概率：中
- 类型：B
- 原因：消息入站/出站与 metadata 处理逻辑频繁调整。

10. **`src/agents/subagent-announce.ts` + `src/agents/subagent-spawn.ts`**

- 概率：中
- 类型：B
- 原因：announce chain / nested retry/drop 修复，和本地任务完成通知体验强相关。

---

## 3) 高风险运行时回归点 Top 8（含最小验证步骤）

1. **Telegram streaming 行为（预览/最终消息拆分）**

- 风险：重复发、丢消息、预览与最终内容不一致。
- 最小验证：
  - 向同一 chat 连续发送 3 条长回复（含工具调用）
  - 检查是否出现重复/截断/乱序
  - 验证 streamMode 各模式下最终消息一致性

2. **Channel thread-aware model override**

- 风险：线程内模型覆盖未生效或越权继承到非线程。
- 最小验证：
  - 在主频道与线程分别设置不同模型
  - 各发 2 条请求，检查实际使用模型与日志一致

3. **exec/sandbox 默认安全门控与 allowlist 解析**

- 风险：原本可执行命令被拦截，或提示/审批路径变化。
- 最小验证：
  - 分别执行 allowlist 内/外命令
  - 验证审批提示、拒绝理由、退出码
  - 验证 heredoc/命令替换被正确拦截

4. **Subagent 路由与 announce chain**

- 风险：子代理完成后不上报、重复上报、线程错位。
- 最小验证：
  - 触发 1 个子任务（含失败重试）
  - 检查开始/结束通知、线程归属、重试后的最终状态

5. **Gateway auth / trusted proxy / loopback 规则**

- 风险：本地控制台可用性下降，或安全策略导致请求被拒。
- 最小验证：
  - 本机 loopback 访问 + 反向代理访问各测一次
  - 验证 health/auth/核心方法权限边界

6. **WhatsApp allowFrom / outbound target 校验收紧**

- 风险：历史可发目标变成 403/拒绝。
- 最小验证：
  - allowFrom 白名单内外各发送一次
  - 核对错误码与提示是否符合预期

7. **Cron 并发与手动运行语义（maxConcurrentRuns、manual marker）**

- 风险：任务漏跑、重复跑、手动 run 干扰正常 due job。
- 最小验证：
  - 建 2 个短周期任务，设置并发限制
  - 手动触发 + 定时触发混测 15 分钟
  - 检查 run-log 连续性与去重

8. **Memory/QMD 可用性与降级路径**

- 风险：索引/检索退化，memory_search unavailable 时行为异常。
- 最小验证：
  - 触发 qmd update + query
  - 故意制造 unavailable 场景，确认 fallback 文案与行为

---

## 4) “现在就合并”建议

**建议：No（不建议立即一把合到生产）**

### 理由

1. 虽然文本冲突概率不一定高（你本地 `main` 不领先 upstream），但 933 提交跨越导致**行为回归面过大**。
2. 关键运行链（gateway、agents、exec、channels、cron）都有语义变化，且与本地日常用法强耦合。
3. 风险主要不在“能不能 merge”，而在“merge 后是否稳定、是否悄悄改变安全/路由/通知行为”。

---

## 5) 若必须合并：最小风险路径（<=4 批）

### 批次 1：安全与输入校验（优先）

- 范围：security fixes、输入校验、脱敏、路径约束（不含大规模 provider/UI 改造）
- 门禁：
  - config/sessions 输出脱敏
  - webhook secret / target 校验
  - allowlist 拦截与错误码一致

### 批次 2：渠道与路由（Telegram/Discord/WhatsApp/Subagent）

- 范围：streaming、thread-aware override、subagent announce/route、channel target 规则
- 门禁：
  - Telegram 三轮长消息稳定性
  - 线程模型覆盖正确
  - 子代理通知链完整

### 批次 3：执行与调度核心（exec + cron + gateway auth/proxy）

- 范围：exec sandbox/approval 语义、cron 并发/marker、gateway proxy/auth 边界
- 门禁：
  - allowlist + sandbox 双路径
  - cron 手动/定时混测
  - loopback 与代理访问一致性

### 批次 4：大面功能与 UI/扩展（可延期）

- 范围：UI 大改、provider 大包、低优先级扩展
- 门禁：
  - 仅在前 3 批稳定后推进
  - 先灰度后全量

---

## 结论

- 面向 `v2026.2.21` 的一次性合并，**工程可行但运行风险高**。
- 最优策略不是“是否合并”，而是“如何分批并设置验证门禁”。
- 当前建议：**先不直接合；若业务强制，按 4 批最小风险路径执行**。
