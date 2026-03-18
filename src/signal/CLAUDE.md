[根目录](../../CLAUDE.md) > [src](../) > **signal**

# Signal Channel

## 模块职责

Signal 通道实现 OpenClaw 与 Signal 消息服务的集成，通过 signal-cli REST API：

1. **消息收发** - 发送和接收 Signal 消息
2. **群组支持** - 群组消息处理
3. **附件处理** - 媒体附件
4. **号码管理** - Signal 号码配置

## 入口与启动

- 主入口：`monitor.ts` - Signal 监控器
- 客户端：`client.ts` - Signal API 客户端
- 配置：通过 `~/.openclaw/config.json` 中的 `signal` 字段

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `monitor.ts` | 主监控器 |
| `client.ts` | API 客户端 |
| `accounts.ts` | 账户管理 |
| `format.ts` | 消息格式化 |

### 消息处理

| 模块 | 职责 |
|------|------|
| `receive.ts` | 消息接收 |
| `send.ts` | 消息发送 |
| `attachments.ts` | 附件处理 |

## 关键依赖与配置

### 外部依赖

- Signal CLI REST API（需要单独运行）

### 配置

```json
{
  "signal": {
    "number": "+1234567890",
    "serverUrl": "http://localhost:8080"
  }
}
```

## 相关文件清单

```
src/signal/
├── monitor.ts              # 主监控器
├── client.ts               # API 客户端
├── accounts.ts             # 账户管理
├── format.ts               # 格式化
├── receive.ts              # 接收
├── send.ts                 # 发送
├── attachments.ts          # 附件
├── groups.ts               # 群组
├── probe.ts                # 探针
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
