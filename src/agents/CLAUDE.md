[根目录](../../CLAUDE.md) > **src** > **agents**

---

# Agents 模块

> AI 代理核心逻辑、认证配置、会话管理

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`src/agents/` 是 OpenClaw 的核心模块，负责：

- **AI 模型集成**：与 Anthropic Claude、OpenAI 等模型的集成
- **认证管理**：API 密钥、OAuth 令牌、认证配置文件管理
- **会话管理**：对话会话的创建、持久化、恢复
- **工具调用**：Bash 工具、文件操作、浏览器自动化等
- **上下文管理**：上下文窗口保护、内容压缩
- **模型目录**：可用模型的发现和过滤

---

## 入口与启动

### 主要入口
- **CLI 入口**: `src/commands/agent.ts` - 通过 `openclaw agent` 命令启动
- **Gateway 入口**: `src/gateway/server-methods/agent.ts` - 通过网关调用

### 关键文件

| 文件 | 描述 |
|------|------|
| `src/agents/agent-paths.ts` | 代理相关路径配置 |
| `src/agents/identity.ts` | 助手身份和配置 |
| `src/agents/auth-profiles/` | 认证配置文件系统 |
| `src/agents/bash-tools.ts` | Bash 工具执行 |
| `src/agents/model-catalog.ts` | 模型目录和发现 |

---

## 对外接口

### Agent 命令
```bash
# 直接对话
openclaw agent --message "你的消息"

# 高推理模式
openclaw agent --message "复杂任务" --thinking high

# 通过网关
openclaw agent --via-gateway
```

### 主要类和函数

#### `Identity`
助手身份配置，包含：
- 名称、头像
- 系统提示词
- 行为配置

#### `AuthProfile`
认证配置文件，支持：
- API 密钥存储
- OAuth 令牌
- 多提供商管理
- 使用量跟踪

#### `BashTools`
Bash 工具执行器：
- PTY 后端支持
- 后台进程管理
- 批准流程集成
- 路径验证

---

## 关键依赖与配置

### 外部依赖
```json
{
  "@anthropic-ai/sdk": "^0.73.0",
  "openai": "^6.18.0",
  "@aws-sdk/client-bedrock": "^3.986.0",
  "@mistralai/mistralai": "^1.10.0"
}
```

### 配置文件
- **存储位置**: `~/.openclaw/agents/`
- **认证配置**: `~/.openclaw/auth-profiles.json`
- **会话存储**: `~/.openclaw/sessions/`

### 环境变量
- `OPENCLAW_LIVE_TEST=1` - 启用实时 API 测试
- `OPENCLAW_E2E_MODELS` - E2E 测试使用的模型

---

## 数据模型

### 认证配置 (AuthProfile)
```typescript
interface AuthProfile {
  id: string;
  provider: 'anthropic' | 'openai' | 'google' | ...;
  type: 'api-key' | 'oauth';
  credentials: Record<string, string>;
  lastUsed?: number;
  usage?: UsageStats;
}
```

### 会话 (Session)
```typescript
interface Session {
  id: string;
  agentId: string;
  messages: Message[];
  createdAt: number;
  updatedAt: number;
}
```

---

## 测试与质量

### 测试文件
- `src/agents/auth-profiles/*.test.ts` - 认证配置测试
- `src/agents/bash-tools.test.ts` - Bash 工具测试
- `src/agents/model-catalog.test.ts` - 模型目录测试

### 运行测试
```bash
# 单元测试
vitest run src/agents

# 实时测试（需要 API）
OPENCLAW_LIVE_TEST=1 vitest run --config vitest.live.config.ts
```

### 测试覆盖
- 认证配置文件管理
- OAuth 流程
- 模型发现和过滤
- Bash 工具执行
- 上下文窗口保护

---

## 常见问题 (FAQ)

### Q: 如何添加新的 AI 模型提供商？
A: 在 `src/agents/` 中创建新的认证配置处理器，实现 `apply` 函数。

### Q: Bash 工具如何处理权限？
A: 通过 `exec-approval` 系统实现批准流程，支持命令白名单和黑名单。

### Q: 如何配置模型回退？
A: 使用 `model-fallback.ts` 中的逻辑，配置主模型和备用模型。

---

## 相关文件清单

### 核心文件
```
src/agents/
├── agent-paths.ts           # 路径配置
├── identity.ts              # 助手身份
├── auth-profiles/           # 认证配置
│   ├── index.ts
│   ├── store.ts
│   ├── oauth.ts
│   └── types.ts
├── bash-tools.ts            # Bash 工具
├── model-catalog.ts         # 模型目录
├── model-compat.ts          # 模型兼容性
├── context-window-guard.ts  # 上下文保护
└── cache-trace.ts           # 缓存跟踪
```

### 测试文件
```
src/agents/
├── *.test.ts                # 各功能单元测试
└── auth-profiles/
    └── *.test.ts            # 认证相关测试
```
