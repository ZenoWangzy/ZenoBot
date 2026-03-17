# OpenClaw 版本调研报告（fallback：GitHub Releases + 本地仓库）

## 1) 最新版本

- **最新稳定版**：`v2026.2.21`
- **发布时间**：`2026-02-21T16:56:48Z`（北京时间 **2026-02-22 00:56:48**）
- **上一稳定版**：`v2026.2.19`
- 备注：发布说明中注明 npm 有后续修正包 **`openclaw@2026.2.21-1`**。

## 2) 相比上一版本（v2026.2.19）的关键变化（3-5条）

1. **模型与提供商扩展**
   - 新增 Gemini 3.1 相关模型支持。
   - 新增/接入 Volcano Engine（豆包）与 BytePlus 多模型（含 coding 变体），并补齐 onboarding 流程。

2. **多渠道消息体验增强（Discord/Telegram）**
   - Telegram 流式预览配置简化为 `channels.telegram.streaming`。
   - Discord 新增流式草稿预览（partial/block、分块策略），并强化生命周期状态 reaction（queued/thinking/tool/done/error）。

3. **子代理与会话路由能力增强**
   - Discord 支持“线程绑定”的 subagent 会话与延续路由。
   - 子代理默认深度策略统一为 `maxSpawnDepth=2`（更一致的生成/提示路径策略）。

4. **内存与 QMD 稳定性修复（高频痛点）**
   - 针对 QMD 多集合检索、启动初始化、索引/嵌入并发、锁冲突与 CPU 风暴做了多项修复。
   - `memory_search` 在不可用场景返回更明确 `unavailable` 警告，减少“误以为空结果”的问题。

5. **安全加固面显著扩大**
   - 多处哈希从 SHA-1 迁移到 SHA-256（锁、合成ID等）。
   - 加强 Exec/Browser/Gateway/UI 等链路的注入、越权、元数据泄露与重定向凭据泄漏防护。

## 3) 升级风险与注意事项

1. **配置项变更风险（中）**
   - Telegram streaming 配置键行为有调整（旧 `streamMode` 自动映射，但建议手工核对）。
   - 建议升级后先执行 `/status` 或相关自检，确认通道模型覆盖和流式配置是否符合预期。

2. **安全策略收紧导致“原可用配置失效”（中-高）**
   - 针对 trusted-proxy、token、exec allowlist、browser 协议/网络访问有更严格限制。
   - 若历史配置较“宽松”，升级后可能出现请求被拒或功能降级。

3. **子代理/路由行为变化（中）**
   - 默认 `maxSpawnDepth=2`、线程绑定路由等可能改变原有调度与输出路径。
   - 建议在生产前用典型任务回归（含 announce、thread、delivery 默认目标）。

4. **增量补丁版本注意（低-中）**
   - 官方说明有 npm 后续补丁（`2026.2.21-1`），建议安装时优先确认实际安装的是最新补丁构建。

---

## 来源链接（官方/可复核）

- 最新版本 Release（v2026.2.21）
  - https://github.com/openclaw/openclaw/releases/tag/v2026.2.21
- 上一版本 Release（v2026.2.19）
  - https://github.com/openclaw/openclaw/releases/tag/v2026.2.19
- GitHub Releases API（用于发布时间与正文抓取）
  - https://api.github.com/repos/openclaw/openclaw/releases?per_page=5
- 本地仓库 remote（用于确认 upstream）
  - `upstream: https://github.com/OpenClaw/openclaw.git`（本地 `git remote -v` 输出）
