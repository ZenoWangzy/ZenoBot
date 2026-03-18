[根目录](../CLAUDE.md) > **extensions**

# Extensions (Plugins)

## 模块职责

Extensions 目录包含所有 OpenClaw 插件，每个插件都是一个独立的 npm 包，可以扩展 OpenClaw 的功能。

## 插件列表

### 通道插件

| 插件 | 通道 | 描述 |
|------|------|------|
| `@openclaw/msteams` | Microsoft Teams | Bot Framework 集成 |
| `@openclaw/matrix` | Matrix | 开放协议支持 |
| `@openclaw/zalo` | Zalo | 越南即时通讯 |
| `@openclaw/zalouser` | Zalo User | Zalo 用户模式 |
| `@openclaw/voice-call` | Voice Call | 语音通话 |
| `@openclaw/irc` | IRC | IRC 协议 |
| `@openclaw/nostr` | Nostr | 去中心化协议 |
| `@openclaw/twitch` | Twitch | 直播平台 |
| `@openclaw/googlechat` | Google Chat | Google Workspace |
| `@openclaw/feishu` | Feishu/Lark | 字节跳动办公套件 |
| `@openclaw/nextcloud-talk` | Nextcloud Talk | Nextcloud 聊天 |
| `@openclaw/tlon` | Tlon | Urbit 协议 |
| `@openclaw/synology-chat` | Synology Chat | 群晖聊天 |
| `@openclaw/mattermost` | Mattermost | 开源团队聊天 |
| `@openclaw/line` | LINE | 日本即时通讯 |
| `@openclaw/bluebubbles` | BlueBubbles | iMessage 代理 |
| `@openclaw/telegram` | Telegram | 备用 Telegram 插件 |
| `@openclaw/discord` | Discord | 备用 Discord 插件 |
| `@openclaw/signal` | Signal | 备用 Signal 插件 |
| `@openclaw/whatsapp` | WhatsApp | 备用 WhatsApp 插件 |
| `@openclaw/imessage` | iMessage | 备用 iMessage 插件 |
| `@openclaw/slack` | Slack | 备用 Slack 插件 |

### 功能插件

| 插件 | 描述 |
|------|------|
| `@openclaw/llm-task` | LLM 任务处理 |
| `@openclaw/lobster` | Lobster 集成 |
| `@openclaw/memory-core` | 记忆核心 |
| `@openclaw/memory-lancedb` | LanceDB 记忆后端 |
| `@openclaw/diffs` | 差异对比 |
| `@openclaw/diagnostics-otel` | OpenTelemetry 诊断 |
| `@openclaw/copilot-proxy` | GitHub Copilot 代理 |
| `@openclaw/open-prose` | Prose 处理 |
| `@openclaw/acpx` | ACP 扩展 |
| `@openclaw/google-gemini-cli-auth` | Gemini CLI 认证 |
| `@openclaw/minimax-portal-auth` | MiniMax 认证 |
| `@openclaw/qwen-portal-auth` | 通义千问认证 |
| `@openclaw/device-pair` | 设备配对 |

## 插件结构

每个插件目录结构：

```
extensions/<name>/
├── package.json      # 包配置和 openclaw 元数据
├── index.ts          # 插件入口
├── src/              # 源代码
│   ├── channel.ts    # 通道实现（如果是通道插件）
│   └── *.ts          # 其他模块
└── *.test.ts         # 测试
```

## 插件配置

插件通过 `package.json` 中的 `openclaw` 字段配置：

```json
{
  "name": "@openclaw/example",
  "version": "2026.3.8",
  "type": "module",
  "dependencies": { ... },
  "openclaw": {
    "extensions": ["./index.ts"],
    "channel": {
      "id": "example",
      "label": "Example Channel",
      "selectionLabel": "Example (plugin)",
      "docsPath": "/channels/example",
      "docsLabel": "example",
      "blurb": "Example channel plugin",
      "order": 100
    },
    "install": {
      "npmSpec": "@openclaw/example",
      "localPath": "extensions/example",
      "defaultChoice": "npm"
    }
  }
}
```

## 开发指南

### 创建新插件

1. 在 `extensions/` 中创建新目录
2. 创建 `package.json` 并添加 `openclaw` 配置
3. 实现 `index.ts` 入口
4. 使用 `openclaw/plugin-sdk` API

### 依赖管理

- 插件专用依赖放在插件的 `dependencies`
- 不要添加到根 `package.json`
- 避免在 `dependencies` 中使用 `workspace:*`
- 将 `openclaw` 放在 `devDependencies` 或 `peerDependencies`

### 测试

- 测试文件命名为 `*.test.ts`
- 使用 Vitest 框架

## 相关文件

- [根目录 CLAUDE.md](../CLAUDE.md)
- [插件运行时](../src/plugins/CLAUDE.md)
- [Plugin SDK](../src/plugin-sdk/)

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
