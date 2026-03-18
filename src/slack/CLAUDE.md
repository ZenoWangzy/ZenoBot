[根目录](../../CLAUDE.md) > [src](../) > **slack**

# Slack Channel

## 模块职责

Slack 通道实现 OpenClaw 与 Slack API 的集成，包括：

1. **Socket Mode** - 通过 WebSocket 接收 Slack 事件
2. **消息处理** - 接收和发送 Slack 消息
3. **Block Kit** - 支持 Slack Block Kit 组件
4. **模态框** - 交互式模态框
5. **应用命令** - 斜杠命令支持

## 入口与启动

- 主入口：`monitor.ts` - Slack 监控器
- 客户端：`client.ts` - Slack API 客户端
- HTTP：`http/registry.ts` - HTTP 端点注册

## 对外接口

### 核心

| 模块 | 职责 |
|------|------|
| `monitor.ts` | 主监控器 |
| `client.ts` | API 客户端 |
| `accounts.ts` | 账户管理 |
| `actions.ts` | 动作处理 |

### 消息处理

| 模块 | 职责 |
|------|------|
| `monitor/message-handler.ts` | 消息处理 |
| `monitor/context.ts` | 消息上下文 |
| `monitor/replies.ts` | 回复处理 |

### Block Kit

| 模块 | 职责 |
|------|------|
| `blocks-input.ts` | Block 输入 |
| `blocks-fallback.ts` | Block 回退 |

### 事件

| 模块 | 职责 |
|------|------|
| `monitor/events.ts` | 事件分发 |
| `monitor/events/messages.ts` | 消息事件 |
| `monitor/events/interactions.ts` | 交互事件 |
| `monitor/events/reactions.ts` | 反应事件 |

## 关键依赖与配置

### 外部依赖

- `@slack/bolt` - Slack Bolt 框架
- `@slack/web-api` - Slack Web API

### 配置

```json
{
  "slack": {
    "botToken": "xoxb-...",
    "appToken": "xapp-...",
    "signingSecret": "..."
  }
}
```

## 相关文件清单

```
src/slack/
├── monitor.ts              # 主监控器
├── client.ts               # API 客户端
├── accounts.ts             # 账户管理
├── actions.ts              # 动作处理
├── format.ts               # 格式化
├── blocks-input.ts         # Block 输入
├── blocks-fallback.ts      # Block 回退
├── threading.ts            # 线程处理
├── targets.ts              # 目标解析
├── stream-mode.ts          # 流模式
├── streaming.ts            # 流式响应
├── draft-stream.ts         # 草稿流
├── probe.ts                # 探针
├── http/                   # HTTP 端点
│   ├── index.ts            # 入口
│   └── registry.ts         # 注册
├── monitor/                # 监控器组件
│   ├── provider.ts         # 提供者
│   ├── message-handler.ts  # 消息处理
│   ├── context.ts          # 上下文
│   ├── allow-list.ts       # 允许列表
│   ├── auth.ts             # 认证
│   ├── events/             # 事件处理
│   └── ...                 # 其他
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
