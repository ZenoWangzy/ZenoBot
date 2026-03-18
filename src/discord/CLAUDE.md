[根目录](../../CLAUDE.md) > [src](../) > **discord**

# Discord Channel

## 模块职责

Discord 通道实现 OpenClaw 与 Discord Gateway API 的集成，包括：

1. **Gateway 连接** - 通过 WebSocket 连接到 Discord
2. **消息处理** - 接收和发送 Discord 消息
3. **线程支持** - 自动线程创建和管理
4. **组件交互** - 按钮和选择菜单
5. **状态管理** - 机器人状态和活动

## 入口与启动

- 主入口：`monitor.ts` - Discord 监控器
- 客户端：`client.ts` - Discord API 客户端
- Gateway：`monitor/gateway.ts` - Gateway 连接

## 对外接口

### 核心

| 模块 | 职责 |
|------|------|
| `monitor.ts` | 主监控器 |
| `client.ts` | API 客户端 |
| `accounts.ts` | 账户管理 |
| `send.ts` | 消息发送 |

### 消息处理

| 模块 | 职责 |
|------|------|
| `monitor/message-handler.ts` | 消息处理 |
| `monitor/inbound-job.ts` | 入站作业 |
| `monitor/inbound-context.ts` | 入站上下文 |

### 线程

| 模块 | 职责 |
|------|------|
| `monitor/thread-bindings.ts` | 线程绑定 |
| `monitor/threading.ts` | 线程管理 |

### 组件

| 模块 | 职责 |
|------|------|
| `components.ts` | 组件定义 |
| `monitor/agent-components.ts` | 代理组件 |

## 关键依赖与配置

### 外部依赖

- `discord-api-types` - Discord API 类型
- `@discordjs/voice` - 语音支持

### 配置

```json
{
  "discord": {
    "botToken": "YOUR_BOT_TOKEN",
    "applicationId": "YOUR_APP_ID"
  }
}
```

## 相关文件清单

```
src/discord/
├── monitor.ts              # 主监控器
├── client.ts               # API 客户端
├── accounts.ts             # 账户管理
├── send.ts                 # 消息发送
├── api.ts                  # API 调用
├── components.ts           # 组件定义
├── mentions.ts             # 提及处理
├── chunk.ts                # 消息分块
├── guilds.ts               # 服务器管理
├── audit.ts                # 审计
├── probe.ts                # 探针
├── format.ts               # 格式化
├── monitor/                # 监控器组件
│   ├── gateway.ts          # Gateway 连接
│   ├── message-handler.ts  # 消息处理
│   ├── thread-bindings.ts  # 线程绑定
│   ├── allow-list.ts       # 允许列表
│   └── ...                 # 其他
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
