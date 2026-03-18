[根目录](../../CLAUDE.md) > [src](../) > **channels**

# Channels

## 模块职责

Channels 模块是 OpenClaw 通道抽象层的核心，负责：

1. **通道接口定义** - 定义所有消息通道的统一接口
2. **通道注册** - 管理内置通道和插件通道的注册
3. **消息格式转换** - 统一不同通道的消息格式
4. **通道能力** - 定义通道支持的功能（文本、图片、文件等）

## 入口与启动

- 主入口：`index.ts`
- 通道注册：通过 `src/plugins/` 和各通道目录自动注册

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 通道导出和注册 |
| `types.ts` | 通道类型定义 |
| `capabilities.ts` | 通道能力定义 |

### 内置通道

| 通道 | 目录 | 描述 |
|------|------|------|
| Telegram | `src/telegram/` | Telegram Bot API |
| Discord | `src/discord/` | Discord Bot |
| Slack | `src/slack/` | Slack App |
| Signal | `src/signal/` | Signal 协议 |
| iMessage | `src/imessage/` | Apple iMessage |
| WhatsApp | `src/web/` | WhatsApp Web |

## 关键依赖与配置

### 内部依赖

- `src/routing/` - 消息路由
- `src/plugins/` - 插件运行时（扩展通道）
- `src/config/` - 配置管理

## 数据模型

### 通道能力

```typescript
interface ChannelCapabilities {
  text: boolean;
  images: boolean;
  files: boolean;
  audio: boolean;
  video: boolean;
  reactions: boolean;
  replies: boolean;
  edits: boolean;
  deletions: boolean;
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖通道注册、能力检查、消息格式转换

## 相关文件清单

```
src/channels/
├── index.ts           # 通道导出
├── types.ts           # 类型定义
├── capabilities.ts    # 能力定义
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
