# 任务计划：合并上游 openclaw v2026.2.26 到本地 Fork

**创建时间**: 2026-02-28
**状态**: 🟡 规划中
**决策**: 浏览器功能采用上游版本，放弃本地增强

---

## 📋 任务概述

将上游 openclaw/openclaw 的 v2026.2.26 及 v2026.2.27 开发版更新合并到本地 fork，同时保留本地独特功能（Watchdog、内存管理增强等）。

---

## 🎯 目标

1. ✅ 获取上游最新功能（395 个提交）
2. ✅ 保留本地独特功能（非浏览器相关）
3. ✅ 解决合并冲突
4. ✅ 确保代码质量

---

## 📊 当前冲突分析

### 🔴 已识别的冲突文件

| 文件                                           | 本地修改 | 上游修改     | 冲突类型  | 处理策略         |
| ---------------------------------------------- | -------- | ------------ | --------- | ---------------- |
| `src/browser/extension-relay.ts`               | +141 行  | +806/-565 行 | 🟢 已决定 | **采用上游版本** |
| `src/auto-reply/reply/dispatch-from-config.ts` | +57 行   | +91 行       | 🟡 待分析 | 需要详细对比     |
| `src/agents/pi-embedded-runner/run/attempt.ts` | +33 行   | +155 行      | 🟡 待分析 | 需要详细对比     |

---

## 🔍 冲突分析总结

### ✅ 分析完成

- [x] 识别主要冲突文件（3个）
- [x] 详细分析 `extension-relay.ts` → 采用上游版本
- [x] 详细分析 `dispatch-from-config.ts` → 可手动合并（互补功能）
- [x] 详细分析 `attempt.ts` → 可手动合并（互补功能）
- [x] 检查其他文件冲突 → 无冲突

### 🎉 好消息

**除了浏览器功能（已决定采用上游），其他所有冲突都可以通过手动合并解决！**

所有本地独特功能（watchdog、memory、schtasks 等）都是独立新增，上游未触及，无冲突风险。

---

## 📅 阶段计划

### Phase 1: 冲突分析 ✅ 完成

- [x] 识别主要冲突文件（3个）
- [x] 详细分析每个冲突
- [x] 确定处理策略
- [x] 检查其他文件（无冲突）

**结果**:

- `extension-relay.ts` → 采用上游版本
- `dispatch-from-config.ts` → 手动合并（低风险）
- `attempt.ts` → 手动合并（低风险）
- 其他本地功能 → 无冲突

### Phase 2: 准备工作 🟡 待执行

- [ ] 创建备份分支 `backup-before-merge`
- [ ] 创建合并测试分支 `merge-upstream-2026.2.26`
- [ ] 设置测试环境

### Phase 3: 执行合并 ⚪ 待开始

- [ ] 合并上游代码 `git merge upstream/main`
- [ ] 解决 `dispatch-from-config.ts` 冲突
- [ ] 解决 `attempt.ts` 冲突
- [ ] 采用上游 `extension-relay.ts` 版本
- [ ] 验证合并结果

### Phase 4: 测试验证 ⚪ 待开始

- [ ] 运行测试套件 `pnpm test`
- [ ] 验证本地功能（watchdog、memory）
- [ ] 验证上游新功能（secrets、ACP）
- [ ] 运行 lint 检查 `pnpm check`

---

## 🧪 测试计划

### 基础测试

```bash
# 1. 类型检查和构建
pnpm build

# 2. Lint 和格式检查
pnpm check

# 3. 运行完整测试套件
pnpm test

# 4. 测试覆盖率（可选）
pnpm test:coverage
```

### 本地功能验证测试

```bash
# Watchdog 功能测试
pnpm test src/daemon/watchdog.test.ts

# 内存管理测试
pnpm test src/memory/

# Windows 定时任务测试
pnpm test src/daemon/schtasks.test.ts

# 错误处理测试（dispatch-from-config）
pnpm test src/auto-reply/reply/
```

### 上游新功能验证

```bash
# Secrets 管理测试
pnpm test src/cli/secrets-cli.test.ts

# ACP 代理测试
pnpm test src/acp/

# 代理路由测试
pnpm test src/agents/bindings.test.ts
```

### 集成测试

```bash
# 浏览器扩展测试（验证上游版本）
pnpm test src/browser/

# Pi 嵌入式运行器测试（验证 attempt.ts 合并）
pnpm test src/agents/pi-embedded-runner/
```

### 关键验证点

- [ ] 所有单元测试通过
- [ ] 无 TypeScript 类型错误
- [ ] 无 Lint 错误
- [ ] 本地 watchdog 功能正常
- [ ] 本地 memory 功能正常
- [ ] 上游 secrets 功能正常
- [ ] 上游 ACP 功能正常
- [ ] 错误处理功能正常（dispatch-from-config.ts）
- [ ] 内存预加载功能正常（attempt.ts）

---

## 📝 决策记录

### 2026-02-28

- **决策**: 浏览器功能采用上游版本
- **原因**: 上游进行了大规模重构，本地增强需要重新适配
- **影响**: 放弃本地浏览器自动重连功能，使用上游实现
