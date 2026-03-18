[根目录](../../CLAUDE.md) > [src](../) > **plugin-sdk**

# Plugin SDK

## 模块职责

Plugin SDK 模块提供插件开发的核心 SDK，包括：

1. **插件 API** - 插件开发的核心接口
2. **通道 SDK** - 各通道的专用 SDK
3. **工具函数** - 插件开发的辅助工具
4. **类型定义** - 插件相关的类型

## 入口与启动

- 主入口：`index.ts`
- 核心：`core.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | SDK 主入口 |
| `core.ts` | 核心 API |
| `compat.ts` | 兼容层 |

### 通道 SDK

| SDK | 模块 | 描述 |
|-----|------|------|
| Telegram | `telegram.ts` | Telegram 插件 SDK |
| Discord | `discord.ts` | Discord 插件 SDK |
| Slack | `slack.ts` | Slack 插件 SDK |
| Signal | `signal.ts` | Signal 插件 SDK |
| iMessage | `imessage.ts` | iMessage 插件 SDK |
| WhatsApp | `whatsapp.ts` | WhatsApp 插件 SDK |
| LINE | `line.ts` | LINE 插件 SDK |
| MSTeams | `msteams.ts` | MSTeams 插件 SDK |
| ACP | `acpx.ts` | ACP 扩展 SDK |
| BlueBubbles | `bluebubbles.ts` | BlueBubbles SDK |

### 工具模块

| 模块 | 职责 |
|------|------|
| `account-id.ts` | 账户 ID 处理 |
| `account-resolution.ts` | 账户解析 |
| `allow-from.ts` | 来源验证 |
| `allowlist-resolution.ts` | 白名单解析 |
| `boolean-param.ts` | 布尔参数 |
| `agent-media-payload.ts` | 媒体载荷 |

## 关键依赖与配置

### 导出路径

```json
{
  "exports": {
    "./plugin-sdk": "./dist/plugin-sdk/index.js",
    "./plugin-sdk/core": "./dist/plugin-sdk/core.js",
    "./plugin-sdk/telegram": "./dist/plugin-sdk/telegram.js",
    "./plugin-sdk/discord": "./dist/plugin-sdk/discord.js"
  }
}
```

### 使用方式

```typescript
// 在插件中导入
import { defineChannelPlugin } from 'openclaw/plugin-sdk';
import { telegramHelpers } from 'openclaw/plugin-sdk/telegram';
```

## 测试与质量

- 测试文件：`*.test.ts`
- 测试工具：`test-utils.ts`

## 相关文件清单

```
src/plugin-sdk/
├── index.ts                       # SDK 主入口
├── core.ts                        # 核心 API
├── compat.ts                      # 兼容层
├── telegram.ts                    # Telegram SDK
├── discord.ts                     # Discord SDK
├── slack.ts                       # Slack SDK
├── signal.ts                      # Signal SDK
├── imessage.ts                    # iMessage SDK
├── whatsapp.ts                    # WhatsApp SDK
├── line.ts                        # LINE SDK
├── msteams.ts                     # MSTeams SDK
├── acpx.ts                        # ACP SDK
├── bluebubbles.ts                 # BlueBubbles SDK
├── account-id.ts                  # 账户 ID
├── account-resolution.ts          # 账户解析
├── allow-from.ts                  # 来源验证
├── allowlist-resolution.ts        # 白名单
├── test-utils.ts                  # 测试工具
└── *.test.ts                      # 测试
```

## 相关模块

- [src/plugins/](../plugins/CLAUDE.md) - 插件运行时
- [extensions/](../../extensions/CLAUDE.md) - 扩展插件

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
