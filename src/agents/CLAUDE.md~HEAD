[根目录](../../CLAUDE.md) > [src](../) > **agents**

# Agents

## 模块职责

Agents 模块是 OpenClaw 的 AI 代理运行时核心，负责：

1. **代理执行** - 运行 AI 对话循环
2. **会话管理** - 管理对话历史和上下文
3. **工具调用** - 处理 AI 工具使用请求
4. **流式响应** - 实时流式输出 AI 响应
5. **上下文构建** - 构建提示词和消息历史

## 入口与启动

- 主入口：`agent-loop.ts` - `runAgentLoop()`
- 会话管理：`session-manager.ts`
- 上下文构建：`context/` 目录

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `agent-loop.ts` | 代理执行主循环 |
| `session-manager.ts` | 会话管理器 |
| `agent-protocol.ts` | 代理协议定义 |
| `agent-types.ts` | 类型定义 |

### 上下文构建

| 模块 | 职责 |
|------|------|
| `context/build-messages.ts` | 消息构建 |
| `context/build-system.ts` | 系统提示构建 |
| `context/build-tools.ts` | 工具定义构建 |
| `context/token-limits.ts` | Token 限制处理 |

### 工具处理

| 模块 | 职责 |
|------|------|
| `tool-agent.ts` | 工具代理 |
| `tool-calls.ts` | 工具调用处理 |
| `tool-result.ts` | 工具结果处理 |

### 流式处理

| 模块 | 职责 |
|------|------|
| `stream-agent.ts` | 流式代理 |
| `stream-utils.ts` | 流工具函数 |
| `parts-stream.ts` | 部分流 |

## 关键依赖与配置

### 提供者依赖

- `src/providers/` - LLM 提供者集成
- `src/providers/openai/` - OpenAI
- `src/providers/anthropic/` - Anthropic
- `src/providers/google/` - Google AI

### 配置

```json
{
  "agent": {
    "model": "claude-3-5-sonnet",
    "systemPrompt": "...",
    "maxTokens": 4096,
    "temperature": 0.7
  }
}
```

## 数据模型

### 会话数据

会话存储在 `~/.openclaw/sessions/` 目录：

- `messages.jsonl` - 消息历史
- `context.json` - 上下文状态
- `metadata.json` - 元数据

### 消息格式

```typescript
interface Message {
  id: string;
  role: "user" | "assistant" | "system";
  content: string | ContentPart[];
  timestamp: number;
  parentId?: string;
}
```

## 测试与质量

- 测试覆盖：agent-loop、session-manager、context、tool-calls
- E2E 测试：`*.e2e.test.ts`

## 常见问题 (FAQ)

### 如何添加新的工具？

1. 在 `src/tools/` 中定义工具
2. 在 `context/build-tools.ts` 中注册
3. 在 `tool-calls.ts` 中添加处理逻辑

### 如何调试代理问题？

1. 检查会话日志：`~/.openclaw/sessions/<session-id>/`
2. 启用详细日志：`DEBUG=openclaw:agent:*`
3. 检查上下文构建：`DEBUG=openclaw:context:*`

## 相关文件清单

```
src/agents/
├── agent-loop.ts           # 主循环
├── session-manager.ts      # 会话管理
├── agent-protocol.ts       # 协议
├── agent-types.ts          # 类型
├── tool-agent.ts           # 工具代理
├── tool-calls.ts           # 工具调用
├── tool-result.ts          # 工具结果
├── stream-agent.ts         # 流式代理
├── stream-utils.ts         # 流工具
├── parts-stream.ts         # 部分流
├── context/                # 上下文构建
│   ├── build-messages.ts   # 消息构建
│   ├── build-system.ts     # 系统提示
│   ├── build-tools.ts      # 工具定义
│   └── token-limits.ts     # Token 限制
├── providers/              # 提供者适配
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
