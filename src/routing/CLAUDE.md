[根目录](../../CLAUDE.md) > [src](../) > **routing**

# Routing

## 模块职责

Routing 模块负责消息路由和会话键解析，包括：

1. **会话键解析** - 将消息路由到正确的会话
2. **代理绑定** - 将会话绑定到特定代理配置
3. **通道路由** - 处理不同通道的路由逻辑
4. **会话持久化** - 管理会话存储位置

## 入口与启动

- 主入口：`session-key.ts` - `resolveSessionKey()`
- 路由器：`router.ts` - 消息路由器

## 对外接口

### 核心

| 模块 | 职责 |
|------|------|
| `session-key.ts` | 会话键解析 |
| `router.ts` | 消息路由 |
| `session-route.ts` | 会话路由 |
| `bindings.ts` | 绑定管理 |

### 通道特定

| 模块 | 职责 |
|------|------|
| `telegram.ts` | Telegram 路由 |
| `discord.ts` | Discord 路由 |
| `slack.ts` | Slack 路由 |
| `web.ts` | WhatsApp 路由 |

## 关键依赖与配置

### 绑定配置

```json
{
  "bindings": {
    "telegram:123456": "agent-id-1",
    "discord:789012": "agent-id-2"
  }
}
```

## 数据模型

### 会话键

```typescript
interface SessionKey {
  channel: string;
  conversationId: string;
  userId?: string;
}
```

## 相关文件清单

```
src/routing/
├── session-key.ts          # 会话键解析
├── router.ts               # 消息路由
├── session-route.ts        # 会话路由
├── bindings.ts             # 绑定管理
├── telegram.ts             # Telegram 路由
├── discord.ts              # Discord 路由
├── slack.ts                # Slack 路由
├── web.ts                  # WhatsApp 路由
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
