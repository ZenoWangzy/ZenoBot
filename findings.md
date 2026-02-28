# 研究发现：上游合并冲突分析

**更新时间**: 2026-02-28

---

## 🔍 冲突文件详细分析

### 1. src/browser/extension-relay.ts

**状态**: ✅ 已决定采用上游版本

**本地修改**:

- 添加了浏览器自动重连功能
- 操作重试机制
- +141 行新增代码

**上游修改**:

- 大规模架构重构
- CORS 处理改进
- 扩展认证增强
- 重连弹性改进
- +806/-565 行变更

**结论**: 上游已包含类似功能，采用上游版本。

---

### 2. src/auto-reply/reply/dispatch-from-config.ts

**状态**: ✅ 可合并（互补功能）

**本地修改**:

- 添加错误处理和用户友好的错误消息格式化
- `formatErrorForUser` 函数：处理 429、401、403、timeout 等错误
- 在发生错误时发送错误消息给用户
- +61 行新增代码

**上游修改**:

- 重构 session store entry 解析逻辑
- 添加 ACP 调度支持 (`tryDispatchAcpReply`)
- 添加打字指示器策略 (`resolveRunTypingPolicy`)
- 改进路由逻辑和内部消息通道处理
- +91 行新增代码

**冲突分析**:

- ✅ **无逻辑冲突**：本地修改是错误处理增强，上游是功能扩展
- ✅ **位置不重叠**：本地修改在文件末尾（错误处理），上游修改在中段（调度逻辑）
- ✅ **可合并**：两个修改可以共存，互不影响

**合并策略**: 保留两边的修改，手动合并

---

### 3. src/agents/pi-embedded-runner/run/attempt.ts

**状态**: ✅ 可合并（互补功能）

**本地修改**:

- 添加内存预加载功能（memory preload）
- 在发送提示前基于用户消息预加载相关内存
- 使用 `preloadMemory` 和 `formatPreloadedMemorySection`
- +33 行新增代码（在提示构建阶段）

**上游修改**:

- 添加工具调用名称修剪功能（去除空格）
- `trimWhitespaceFromToolCallNamesInMessage` 函数
- `wrapStreamFnTrimToolCallNames` 包装器
- 重构历史图片处理（移除 `injectHistoryImagesIntoMessages`）
- +155 行变更（在工具调用处理阶段）

**冲突分析**:

- ✅ **无逻辑冲突**：本地是内存预加载（提示前），上游是工具调用处理（提示后）
- ✅ **功能互补**：两个功能在不同阶段工作，不互相干扰
- ✅ **可合并**：修改位置不同，可以共存

**合并策略**: 保留两边的修改，手动合并

---

## 📊 本地独特功能清单

### ✅ 保留功能（非浏览器相关）

1. **Watchdog 守护进程**
   - 文件: `src/daemon/watchdog.ts`
   - 测试: `src/daemon/watchdog.test.ts`
   - 状态: 独立模块，冲突风险低

2. **内存管理增强**
   - 文件: `src/memory/*` (多个文件)
   - 功能: 分层、预加载、健康检查
   - 状态: 独立模块，冲突风险低

3. **CLI 内存命令**
   - 文件: `src/cli/memory-cli.ts`
   - 状态: 新增文件，无冲突

4. **Windows 定时任务增强**
   - 文件: `src/daemon/schtasks.ts`
   - 状态: 需要检查上游是否有更新

---

## 🎯 最终风险评估

### 🟢 无风险或低风险

- **所有独立模块**：watchdog、memory、CLI 命令、设计文档
- **daemon/schtasks.ts**: 本地修改，上游未触及
- **dispatch-from-config.ts**: ✅ 互补功能，可合并
- **attempt.ts**: ✅ 互补功能，可合并

### 🟢 已决定

- **extension-relay.ts**: 采用上游版本

---

## ✅ 最终结论

**好消息！除了浏览器功能（已决定采用上游版本），其他所有冲突都可以通过手动合并解决，且风险很低。**

### 冲突总结

1. ✅ `extension-relay.ts` - 采用上游（已决定）
2. ✅ `dispatch-from-config.ts` - 手动合并（互补功能）
3. ✅ `attempt.ts` - 手动合并（互补功能）

### 其他文件

- ✅ **无冲突**：所有其他本地功能（watchdog、memory、schtasks 等）都是独立新增，上游未触及
