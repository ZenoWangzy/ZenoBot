[根目录](../../CLAUDE.md) > [src](../) > **web**

# Web (WhatsApp) Channel

## 模块职责

Web 通道实现 OpenClaw 与 WhatsApp Web 的集成，通过 Baileys 库：

1. **二维码登录** - 扫码登录 WhatsApp
2. **消息收发** - 发送和接收 WhatsApp 消息
3. **群组支持** - 群组消息和广播列表
4. **媒体处理** - 图片、视频、文档等
5. **会话管理** - WhatsApp 会话持久化

## 入口与启动

- 主入口：`channel-web.ts` - `monitorWebChannel()`
- 自动回复：`auto-reply.ts` - 自动回复处理器
- 登录：`login.ts` - 二维码登录流程

## 对外接口

### 核心

| 模块 | 职责 |
|------|------|
| `channel-web.ts` | 通道入口 |
| `accounts.ts` | 账户管理 |
| `login.ts` | 登录流程 |
| `login-qr.ts` | 二维码登录 |
| `session.ts` | 会话管理 |

### 消息处理

| 模块 | 职责 |
|------|------|
| `inbound.ts` | 入站消息 |
| `inbound/monitor.ts` | 消息监控 |
| `inbound/access-control.ts` | 访问控制 |
| `inbound/media.ts` | 媒体处理 |
| `outbound.ts` | 出站消息 |

### 自动回复

| 模块 | 职责 |
|------|------|
| `auto-reply.ts` | 自动回复入口 |
| `auto-reply/monitor.ts` | 监控器 |
| `auto-reply/deliver-reply.ts` | 回复投递 |

## 关键依赖与配置

### 外部依赖

- `@whiskeysockets/baileys` - WhatsApp Web API

### 配置

```json
{
  "web": {
    "sessionPath": "~/.openclaw/sessions/whatsapp",
    "allowFrom": ["1234567890"]
  }
}
```

## 相关文件清单

```
src/web/
├── channel-web.ts          # 通道入口（在 src/）
├── accounts.ts             # 账户管理
├── login.ts                # 登录流程
├── login-qr.ts             # 二维码登录
├── session.ts              # 会话管理
├── auth-store.ts           # 认证存储
├── inbound.ts              # 入站消息
├── outbound.ts             # 出站消息
├── media.ts                # 媒体处理
├── qr-image.ts             # 二维码图像
├── vcard.ts                # vCard 处理
├── reconnect.ts            # 重连
├── active-listener.ts      # 活动监听器
├── auto-reply.ts           # 自动回复入口
├── auto-reply/             # 自动回复组件
│   ├── monitor.ts          # 监控器
│   ├── deliver-reply.ts    # 回复投递
│   ├── heartbeat-runner.ts # 心跳
│   └── monitor/            # 监控器子组件
├── inbound/                # 入站处理
│   ├── monitor.ts          # 监控
│   ├── access-control.ts   # 访问控制
│   ├── media.ts            # 媒体
│   ├── send-api.ts         # 发送 API
│   └── types.ts            # 类型
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
