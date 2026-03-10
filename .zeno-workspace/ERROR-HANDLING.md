# ERROR-HANDLING.md - 错误处理和恢复机制

> 本文件定义 zenomacbot 如何处理错误和从故障中恢复
> 错误无法避免，关键是如何优雅地处理和快速恢复

---

## 🚨 错误分类（Error Classification）

### 1. 致命错误（Fatal Errors）

**定义**：系统无法继续运行的错误

**示例：**

- 核心配置文件损坏（IDENTITY.md, SOUL.md）
- 数据库/存储不可访问
- 系统崩溃无法恢复

**处理方式：**

- 立即停止处理
- 记录详细错误日志
- 通知用户（如果可能）
- 进入"紧急模式"

---

### 2. 严重错误（Critical Errors）

**定义**：功能严重受限，但系统可以运行

**示例：**

- 配置文件格式错误
- 技能完全无法加载
- 记忆文件损坏或丢失

**处理方式：**

- 禁用相关功能
- 使用回退配置
- 记录错误
- 通知用户功能受限

---

### 3. 警告级别（Warnings）

**定义**：功能轻微受限，但可以继续

**示例：**

- 部分技能加载失败
- 配置项缺失（使用默认值）
- 记忆搜索未找到结果

**处理方式：**

- 记录警告
- 使用默认值或回退方案
- 继续执行
- 在会话结束时提醒用户

---

### 4. 信息级别（Informational）

**定义**：非错误，但值得记录

**示例：**

- 配置文件更新
- 记忆整理完成
- 技能加载成功

**处理方式：**

- 记录到日志
- 不通知用户

---

## 🔄 回退策略（Fallback Strategies）

### 配置文件回退

#### 主配置文件损坏

**优先级顺序：**

1. Git 历史 - 从最近的提交恢复
2. 本地备份 - 从 `backup/` 目录恢复
3. 紧急配置 - 使用最小可用配置

**具体回退：**

| 文件           | 回退来源             | 最小配置 |
| -------------- | -------------------- | -------- |
| `IDENTITY.md`  | backup/IDENTITY.md   | 默认身份 |
| `SOUL.md`      | backup/SOUL.md       | 默认人格 |
| `BOT-RULES.md` | backup/BOT-RULES.md  | 基本规则 |
| `MEMORY.md`    | memory/\*.md（重建） | 空       |

---

### 技能回退

**技能加载失败时：**

1. 禁用该技能
2. 记录错误详情
3. 通知用户
4. 检查是否有可用的替代技能

**示例：**

```
WhatsApp 技能加载失败
    ↓
禁用 WhatsApp
    ↓
记录：ERROR - WhatsApp skill failed to load
    ↓
通知用户："WhatsApp 暂时不可用，其他通道正常"
    ↓
检查是否有替代（Telegram）
```

---

### 记忆回退

**记忆文件损坏时：**

1. 检查 Git 历史
2. 从最近的良好版本恢复
3. 如果没有备份：
   - 从 memory/\*.md 重建 MEMORY.md
   - 重建可能不完整，但总比没有好

**重建策略：**

```bash
# 从 daily notes 重建长期记忆
grep -h "## " memory/*.md | sort | uniq > MEMORY-rebuilt.md
```

---

## 🚑 紧急模式（Emergency Mode）

### 触发条件

- 所有主配置文件损坏
- 系统无法正常初始化
- 用户明确请求紧急模式

### 紧急模式特点

- **最小配置**：只使用硬编码的基本人格
- **无记忆**：不访问任何记忆文件
- **只读**：不写入任何文件
- **通知用户**：明确告知处于紧急模式

### 紧急模式人格

```markdown
# Emergency Mode Persona

- Identity: zenomacbot (Emergency Mode)
- Tone: Professional, cautious
- Capabilities: Basic conversation only
- Memory: None (session only)
- Actions: Read-only (no writes)
```

### 退出紧急模式

- 用户修复配置文件
- 系统重新初始化
- 恢复到正常模式

---

## 📝 错误日志（Error Logging）

### 日志格式

**致命错误：**

```
[FATAL] [2026-02-07 21:43:15] SOUL.md corrupted
    File: SOUL.md
    Error: Invalid YAML/JSON format at line 15
    Context: Expected key-value pair, found unexpected token
    Action: Entering emergency mode
    Recovery: Restoring from backup/SOUL.md
```

**严重错误：**

```
[CRITICAL] [2026-02-07 21:45:20] WhatsApp skill failed to load
    Skill: whatsapp
    Error: Configuration file not found
    Action: Disabling WhatsApp
    Fallback: Using other channels (Telegram if available)
```

**警告：**

```
[WARNING] [2026-02-07 21:47:35] Memory search returned no results
    Query: "感情观"
    Action: Using general knowledge
    Note: This may indicate missing memory data
```

### 日志位置

- **主日志**：`~/.openclaw/logs/errors.log`
- **每日日志**：`~/.openclaw/logs/errors-YYYY-MM-DD.log`

---

## 🔍 错误检测（Error Detection）

### 配置文件验证

**启动时检查：**

```markdown
## 配置文件验证清单

- [x] IDENTITY.md 存在且格式正确
- [x] SOUL.md 存在且格式正确
- [x] BOT-RULES.md 存在且格式正确
- [x] MEMORY.md 存在且格式正确
- [x] memory/ 目录存在
- [ ] 至少有一个 daily note
```

**如果检测到错误：**

1. 标记为警告或致命（根据影响）
2. 尝试自动修复（如果可能）
3. 记录详细错误信息
4. 通知用户（如果是致命错误）

---

### 记忆完整性检查

**每周执行一次：**

1. 验证 MEMORY.md 的格式
2. 验证记忆文件的存在性
3. 检查 memory/\*.md 的日期连续性（不要求每天都有）
4. 验证 MEMORY.md 和 memory/\*.md 的一致性

**发现不一致时：**

1. 记录警告
2. 提示用户需要整理
3. 可以选择自动重新整理

---

## 🛠️ 错误修复（Error Recovery）

### 自动修复

**可以自动修复的错误：**

- 配置文件格式轻微错误（JSON/YAML）
- 记忆文件中缺少的标题
- 日志文件过大（自动轮转）

**修复策略：**

```bash
# 示例：修复 JSON 格式错误
jq '.' broken-config.json > fixed-config.json
```

### 手动修复

**需要用户介入的错误：**

- 核心人格文件损坏（SOUL.md）
- 重要记忆丢失
- 系统配置完全错误

**修复步骤：**

1. 记录详细错误信息
2. 提供修复建议
3. 引导用户完成修复
4. 验证修复成功

---

## 📊 错误统计（Error Statistics）

### 跟踪指标

**每周统计：**

- 错误总数（按级别）
- 最常见的错误类型
- 平均恢复时间
- 自动修复成功率 vs 手动修复

**示例报告：**

```markdown
# 错误周报 - Week 6 (2026-02-01 to 2026-02-07)

## 错误统计

- Fatal: 0
- Critical: 1 (WhatsApp skill load failure)
- Warning: 5 (memory search no results)
- Informational: 23

## 最常见错误

1. Memory search no results (5次)
2. Skill load timeout (2次)

## 恢复时间

- 平均：2.3 秒
- 最长：15 秒（critical error）

## 修复成功率

- 自动修复：85%
- 需要用户介入：15%
```

---

## 🚨 告警机制（Alerting）

### 何时告警

- 致命错误：立即告警
- 严重错误：立即告警
- 警告：累计 5 次后告警
- 系统不可用：立即告警

### 告警方式

- WhatsApp 消息（如果可用）
- 日志记录
- 系统通知（如果支持）

---

## 🔄 恢复测试（Recovery Testing）

### 定期测试

**每月测试一次：**

1. 模拟配置文件损坏
2. 验证回退机制工作
3. 模拟技能加载失败
4. 验证紧急模式可以触发
5. 测试从备份恢复

**记录测试结果：**

- 哪些机制工作正常
- 哪些需要改进
- 平均恢复时间

---

**错误处理的核心原则：**

> **不崩溃，不丢失数据，快速恢复。**

即使在最坏情况下，系统也应该以某种形式继续工作，而不是完全停止。
