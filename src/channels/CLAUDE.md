[根目录](../../CLAUDE.md) > **src** > **channels**

---

# Channels 模块

> 多消息渠道集成插件系统

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`src/channels/` 负责集成各种消息平台，使 AI 助手能够在用户已有的通信渠道中工作。

### 支持的渠道

| 渠道 | 状态 | 说明 |
|------|------|------|
| WhatsApp | 稳定 | 使用 `@whiskeysockets/baileys` |
| Telegram | 稳定 | 使用 `grammy` |
| Slack | 稳定 | 使用 `@slack/bolt` |
| Discord | 稳定 | 使用 `discord-api-types` |
| Signal | 稳定 | 使用 `@matrix-org/matrix-sdk-crypto-nodejs` |
| iMessage | 实验性 | 需要 BlueBubbles 服务器 |
| Google Chat | 实验性 | 使用 `@larksuiteoapi/node-sdk` |
| Microsoft Teams | 实验性 | |
| WebChat | 稳定 | WebSocket |

---

## 入口与启动

### 主要入口
- `src/channels/registry.ts` - 渠道注册表
- `src/channels/plugins/` - 各渠道插件实现

### 关键文件

| 文件 | 描述 |
|------|------|
| `src/channels/registry.ts` | 渠道注册和发现 |
| `src/channels/plugins/` | 各渠道插件实现 |
| `src/channels/channel-config.ts` | 渠道配置管理 |

---

## 对外接口

### 添加渠道
```bash
openclaw channels add telegram
openclaw channels add whatsapp
openclaw channels add slack
```

### 列出渠道
```bash
openclaw channels list
```

### 删除渠道
```bash
openclaw channels remove <channel-id>
```

---

## 关键依赖与配置

### 外部依赖
```json
{
  "@whiskeysockets/baileys": "7.0.0-rc.9",
  "grammy": "^1.40.0",
  "@slack/bolt": "^4.6.0",
  "discord-api-types": "^0.38.38"
}
```

### 配置文件
- **存储位置**: `~/.openclaw/channels/`
- **渠道配置**: `~/.openclaw/channels/config.json`

---

## 数据模型

### 渠道配置
```typescript
interface ChannelConfig {
  id: string;
  type: string;
  enabled: boolean;
  config: Record<string, unknown>;
}
```

---

## 测试与质量

### 测试文件
- `src/channels/plugins/outbound/telegram.test.ts`
- `src/channels/plugins/normalize/*.test.ts`

---

## 相关文件清单

```
src/channels/
├── registry.ts              # 渠道注册表
├── channel-config.ts        # 渠道配置
├── plugins/                 # 渠道插件
│   ├── index.ts
│   ├── outbound/           # 出站消息处理
│   ├── normalize/          # 消息标准化
│   ├── onboarding/         # 入门引导
│   └── actions/            # 特定渠道操作
├── web/                    # WebChat 渠道
└── allowlists/             # 白名单管理
```
