# OpenClaw 上游合并安全性分析（只读）

- 分析时间：2026-02-23 13:14 GMT+8
- 本地仓库：`/Users/ZenoWang/.openclaw/workspace/openclaw`
- 约束：**未执行任何 merge/cherry-pick/rebase；未修改任何源码文件**
- 说明：已尝试使用 Claude Code CLI 做只读摘要，但进程被 SIGKILL（超时/阻塞），因此按约定回退为直接 `git`/release 证据分析。

---

## 1) 本地 fork 状态（当前分支、工作区、与上游分叉）

### 当前状态

- 当前分支：`main`
- HEAD：`b251533e03c41d9301c3d6db505290edef872412`
- 工作区：`git status` 干净（无未提交修改）

### 远端配置

- `origin`: `https://github.com/ZenoWangzy/openclaw.git`
- `upstream`: `https://github.com/OpenClaw/openclaw.git`

### 与上游分叉

- `git merge-base main upstream/main` = `b251533e...`（即本地 main 是上游 main 的祖先点）
- `git rev-list --left-right --count main...upstream/main` = `0 2029`
  - 本地领先：0
  - 上游领先：2029

**结论**：当前本地主线没有私有提交压在 `main` 之上，合并冲突概率整体偏低；但上游跨度很大（2029 提交），建议按“分批、按风险级别”吸收。

---

## 2) 上游最新发布/提交观察

### 看到的近期 tag

- `v2026.2.22`（本地 fetch 到的最新稳定 tag）
- 另有 `v2026.2.21` / `v2026.2.19` 等

### upstream/main 头部关键提交（tag 之后）

- `558a0137b` chore(release): bump versions to 2026.2.23
- `382fe8009` refactor!: remove google-antigravity provider support（**破坏性变更**）
- `77c3b142a` Web UI cron 编辑/历史增强（范围较大）
- `78f801e24` Telegram 目标格式校验（小范围修复）

---

## 3) 合并安全分级（优先级 + 风险）

> 目标：优先选“低冲突 + 低回归 + 不破坏本地自定义行为/配置”的变更。

## A. Safe now（可优先合入）

### A1. CLI 配置脱敏

- 参考：`9c87b53c8` / PR #23654
- 变更模块：`src/cli/config-cli.ts`
- 理由：纯安全增强（输出脱敏），接口行为稳定，冲突面小。
- 预期冲突：低（仅 CLI config get 路径）
- 验证清单：
  - `openclaw config get` 对敏感字段是否显示 `***`
  - 非敏感字段读取是否不变

### A2. Session history 凭据脱敏 + webhook secret 强制

- 参考：`d306fc8ef` / PR #16928
- 模块：`src/agents/tools/sessions-history-tool.ts`
- 理由：安全补丁，减少凭据泄露风险。
- 预期冲突：低（工具层逻辑）
- 验证清单：
  - sessions/history 输出中无 token/secret 明文
  - webhook secret 缺失时有明确报错

### A3. web_fetch 隐藏内容剥离（防间接提示注入）

- 参考：`44727dc3a` / PR #21074
- 模块：`src/agents/tools/web-fetch-visibility*.ts`
- 理由：安全面收益高，对业务行为影响可控。
- 预期冲突：低
- 验证清单：
  - 抓取包含隐藏节点页面时，隐藏文本不进入模型上下文
  - 正常可见正文不丢失

### A4. Cron run-log jobId 路径处理加固

- 参考：`259d86335` / PR openclaw#24038
- 模块：`src/cron/run-log.ts`, `src/gateway/protocol/schema/cron.ts`, `src/gateway/server-methods/cron.ts`
- 理由：输入校验/路径加固，属于防御性修复。
- 预期冲突：低~中（若本地改过 cron schema）
- 验证清单：
  - 非法 jobId 被拒绝
  - 合法 jobId 读写日志正常

### A5. Cron 手动运行标记持久化顺序修复

- 参考：`211ab9e4f` / PR #23993
- 模块：`src/cron/service/ops.ts`
- 理由：修复竞态类问题，行为更确定。
- 预期冲突：中低
- 验证清单：
  - 手动 run 后 marker 一致
  - 不出现重复触发/漏触发

### A6. Cron 手动运行后保留到期任务

- 参考：`f6c2e99f5` / PR #23994
- 模块：`src/cron/service/ops.ts`
- 理由：修复任务调度正确性，回归风险较低。
- 预期冲突：中低（与 A5 同区域）
- 验证清单：
  - 手动 run 不会吞掉后续 due jobs
  - 任务执行顺序符合预期

### A7. daemon restart 健康检查超时改进

- 参考：`80f430c2b`
- 模块：`src/cli/daemon-cli/lifecycle.ts`, `restart-health.ts`
- 理由：稳定性提升，通常不影响配置兼容。
- 预期冲突：低
- 验证清单：
  - `openclaw gateway restart` 成功率
  - 失败提示是否更可诊断

### A8. Telegram 发送目标格式校验

- 参考：`78f801e24` / PR #21930
- 模块：`src/cron/service/jobs.ts`
- 理由：输入校验修复，小范围、低副作用。
- 预期冲突：低
- 验证清单：
  - 非法 target 被拒绝并提示
  - 合法 target 发送正常

---

## B. Safe with guardrails（可合入，但要开护栏/灰度）

### B1. exec 默认 sandbox 语义恢复

- 参考：`278331c49`, `45febecf2`
- 模块：`src/agents/bash-tools.exec.ts`
- 风险点：若本地自定义依赖“非 sandbox 默认行为”，可能改变执行路径。
- 预期冲突：中
- 护栏建议：
  - 先在测试/非关键 agent 开启
  - 对比命令执行权限与超时行为
  - 观察 approvals/notify 链路

### B2. Gateway/Chat UI 包装标签清洗

- 参考：`a10ec2607`
- 模块：`src/gateway/server-methods/chat.ts`
- 风险点：若本地前端或插件依赖历史 wrapper markup，显示可能变化。
- 预期冲突：中低
- 护栏建议：
  - 回归测试 directive/tag 渲染
  - 验证富文本/链接/mention 展示

### B3. Cron 目标错误时抑制 fallback 主摘要

- 参考：`a54dc7fe8` / openclaw#24074
- 模块：`src/cron/isolated-agent/run.ts`, `src/cron/service/timer.ts`
- 风险点：通知策略变化，可能影响你当前“失败可见性”。
- 预期冲突：中
- 护栏建议：
  - 对照失败场景（invalid target）
  - 确认告警是否仍在预期渠道出现

### B4. WhatsApp allowFrom 强制

- 参考：`22c901830` / openclaw#20921
- 模块：`src/whatsapp/resolve-outbound-target.ts`
- 风险点：会收紧发送策略，历史“可发”目标可能被拦截。
- 预期冲突：中
- 护栏建议：
  - 先审计 allowFrom 配置
  - 用 staging 号码跑回归

---

## C. Defer（暂缓，高冲突/高回归风险）

### C1. 破坏性：移除 google-antigravity provider

- 参考：`382fe8009`（`refactor!`）
- 影响面：provider/auth/onboard/model-resolution 多模块
- 风险：若本地任何流程仍依赖该 provider，会直接功能中断。
- 建议：未完成 provider 迁移前不要合。

### C2. Mistral 全量接入

- 参考：`d92ba4f8a` / PR #23845
- 影响面：onboard/auth/config/schema/docs/探针，改动很大
- 风险：配置面与模型路由行为变化大，回归面广。
- 建议：单独分支评估，先做配置兼容与成本控制测试。

### C3. Web UI Cron 全编辑/历史增强

- 参考：`77c3b142a` / openclaw#24155
- 影响面：`ui/*` + `cron` + `gateway schema`
- 风险：前后端协议和展示层均变，若本地有 UI 定制冲突概率高。
- 建议：等核心后端补丁稳定后再做 UI 大包升级。

### C4. 版本跨度一次性快进（2029 commits）

- 参考：`main...upstream/main` 总体差异
- 风险：虽然文本冲突不一定高，但行为回归面非常广。
- 建议：按主题分批（security→cron→exec→ui）逐步吸收。

---

## 4) Do NOT merge yet（暂不建议合入）

1. `382fe8009`（移除 google-antigravity provider）
2. `d92ba4f8a`（Mistral 全量能力接入）
3. `77c3b142a`（UI + cron 大改）
4. 任意 secrets/runtime-activation 系列分支（尚未纳入主线稳定窗口前）

原因：这些变更要么是破坏性、要么跨模块过大、要么会触发本地自定义行为/配置迁移成本。

---

## 5) 建议的合并顺序（最小风险路径）

1. **先合安全补丁**：A1/A2/A3/A4
2. **再合 cron 正确性修复**：A5/A6/A8
3. **最后灰度行为语义变更**：B1/B2/B3/B4（逐项开关/回归）
4. **暂缓大改**：C1/C2/C3

---

## 6) 结论

- 当前本地 `main` 对 `upstream/main`：**无本地领先提交，且工作区干净**。
- 可以优先安全吸收一批低风险补丁（安全/校验/cron 正确性）。
- 对执行语义、通知策略、渠道权限收紧等变更，建议“护栏+灰度”。
- 对破坏性 provider 迁移与 UI 大改，当前阶段应明确列入“Do NOT merge yet”。
