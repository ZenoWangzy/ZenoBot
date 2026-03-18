[根目录](../../CLAUDE.md) > [src](../) > **line**

# LINE

## 模块职责

LINE 模块是 LINE Messaging API 通道的实现，负责：

1. **Webhook 处理** - 接收 LINE 平台的消息推送
2. **消息发送** - 通过 LINE API 发送消息
3. **富媒体消息** - 支持图片、视频、Flex 消息等
4. **用户管理** - 管理用户信息和群组

## 入口与启动

- 主入口：`index.ts`
- 需要 LINE Developers 账号和 Channel Access Token

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | LINE 导出 |
| `webhook.ts` | Webhook 处理 |
| `api.ts` | API 调用 |
| `types.ts` | 类型定义 |

## 关键依赖与配置

### 依赖

- `@line/bot-sdk` - LINE Bot SDK

### 配置

```json
{
  "channels": {
    "line": {
      "enabled": true,
      "channelAccessToken": "...",
      "channelSecret": "..."
    }
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 需要 LINE Bot 账号进行 live 测试

## 相关文件清单

```
src/line/
├── index.ts           # LINE 导出
├── webhook.ts         # Webhook 处理
├── api.ts             # API 调用
├── types.ts           # 类型定义
└── *.test.ts          # 测试
```

## 相关模块

- [extensions/line](../../extensions/line/) - LINE 插件

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
