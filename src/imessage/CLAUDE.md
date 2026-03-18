[根目录](../../CLAUDE.md) > [src](../) > **imessage**

# iMessage Channel

## 模块职责

iMessage 通道实现 OpenClaw 与 macOS iMessage 的集成：

1. **消息收发** - 发送和接收 iMessage
2. **群组支持** - 群组消息处理
3. **附件处理** - 媒体附件
4. **联系人管理** - 联系人解析

## 入口与启动

- 主入口：`monitor.ts` - iMessage 监控器
- 数据库访问：`db.ts` - 访问 iMessage 数据库
- 配置：通过 `~/.openclaw/config.json` 中的 `imessage` 字段

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `monitor.ts` | 主监控器 |
| `db.ts` | 数据库访问 |
| `accounts.ts` | 账户管理 |
| `format.ts` | 消息格式化 |

### 消息处理

| 模块 | 职责 |
|------|------|
| `receive.ts` | 消息接收 |
| `send.ts` | 消息发送 |
| `attachments.ts` | 附件处理 |

### macOS 集成

| 模块 | 职责 |
|------|------|
| `apple-script.ts` | AppleScript 执行 |
| `contacts.ts` | 联系人 |

## 关键依赖与配置

### 系统要求

- macOS 10.15+
- 全盘访问权限（访问 iMessage 数据库）

### 配置

```json
{
  "imessage": {
    "enabled": true,
    "allowedFrom": ["+1234567890"]
  }
}
```

## 相关文件清单

```
src/imessage/
├── monitor.ts              # 主监控器
├── db.ts                   # 数据库
├── accounts.ts             # 账户管理
├── format.ts               # 格式化
├── receive.ts              # 接收
├── send.ts                 # 发送
├── attachments.ts          # 附件
├── apple-script.ts         # AppleScript
├── contacts.ts             # 联系人
├── probe.ts                # 探针
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
