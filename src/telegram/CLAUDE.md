[根目录](../../CLAUDE.md) > [src](../) > **telegram**

# Telegram Channel

## 模块职责

Telegram 通道实现 OpenClaw 与 Telegram Bot API 的集成，包括：

1. **消息接收** - 通过长轮询接收 Telegram 更新
2. **消息发送** - 发送文本、媒体、按钮等
3. **群组管理** - 群组访问控制、成员审计
4. **会话绑定** - 将 Telegram 聊天映射到 AI 会话
5. **原生命令** - 内置机器人命令（/start、/help 等）

## 入口与启动

- 主入口：`bot.ts` - `createTelegramBot()`
- 监控器：通过 `src/telegram/monitor.ts` 启动
- 配置：通过 `~/.openclaw/config.json` 中的 `telegram` 字段

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `bot.ts` | 机器人主类 |
| `bot-handlers.ts` | 更新处理器 |
| `bot-updates.ts` | 更新管理 |
| `bot-message.ts` | 消息处理 |
| `bot-message-dispatch.ts` | 消息分发 |

### 消息处理

| 模块 | 职责 |
|------|------|
| `bot-message-context.ts` | 消息上下文构建 |
| `bot-message-context/body.ts` | 消息体解析 |
| `bot-message-context/session.ts` | 会话绑定 |

### 发送

| 模块 | 职责 |
|------|------|
| `bot/delivery.ts` | 消息投递 |
| `bot/delivery.send.ts` | 发送实现 |
| `bot/delivery.resolve-media.ts` | 媒体解析 |
| `bot/reply-threading.ts` | 回复线程 |

### 访问控制

| 模块 | 职责 |
|------|------|
| `group-access.ts` | 群组访问控制 |
| `dm-access.ts` | 私聊访问控制 |
| `bot-access.ts` | 机器人访问控制 |
| `audit.ts` | 审计日志 |
| `audit-membership-runtime.ts` | 成员审计 |

### 格式化

| 模块 | 职责 |
|------|------|
| `format.ts` | 消息格式化 |
| `caption.ts` | 媒体标题 |
| `draft-chunking.ts` | 消息分块 |
| `draft-stream.ts` | 流式草稿 |

### 交互

| 模块 | 职责 |
|------|------|
| `inline-buttons.ts` | 内联按钮 |
| `bot-native-commands.ts` | 原生命令 |
| `bot-native-command-menu.ts` | 命令菜单 |

## 关键依赖与配置

### 外部依赖

- `grammy` - Telegram Bot API 框架
- `@grammyjs/runner` - 长轮询运行器
- `@grammyjs/transformer-throttler` - 请求节流

### 配置

```json
{
  "telegram": {
    "botToken": "YOUR_BOT_TOKEN",
    "allowedChats": ["chat_id"],
    "groupPolicy": "allowlist"
  }
}
```

## 数据模型

### 消息目标

`targets.ts` 定义了消息目标解析，支持：
- 私聊（用户 ID）
- 群组（群组 ID）
- 话题（群组 ID + 话题 ID）

### 贴纸缓存

`sticker-cache.ts` 管理贴纸文件的本地缓存。

## 测试与质量

- 测试辅助：`send.test-harness.ts`、`bot.create-telegram-bot.test-harness.ts`
- 媒体测试：`bot.media.*.ts`
- 覆盖：消息处理、发送、访问控制、格式化、原生命令

## 常见问题 (FAQ)

### 如何添加新的 Telegram 命令？

1. 在 `bot-native-commands.ts` 中添加命令处理器
2. 在 `bot-native-command-menu.ts` 中注册命令菜单
3. 添加对应的测试

### 如何处理 Telegram 的消息限制？

- 使用 `draft-chunking.ts` 自动分割长消息
- 使用 `sendchataction-401-backoff.ts` 处理发送动作回退

### 如何调试 Telegram 问题？

- 检查日志：`tail -f ~/.openclaw/logs/telegram.log`
- 运行探针：`openclaw channels status --probe telegram`

## 相关文件清单

```
src/telegram/
├── bot.ts                      # 机器人主类
├── bot-*.ts                    # 机器人组件
├── bot/                        # 机器人子模块
│   ├── delivery.ts             # 投递
│   ├── helpers.ts              # 辅助函数
│   ├── reply-threading.ts      # 回复线程
│   └── types.ts                # 类型
├── format.ts                   # 格式化
├── caption.ts                  # 标题
├── targets.ts                  # 目标解析
├── accounts.ts                 # 账户管理
├── account-inspect.ts          # 账户检查
├── probe.ts                    # 探针
├── fetch.ts                    # API 请求
├── voice.ts                    # 语音消息
├── inline-buttons.ts           # 内联按钮
├── reaction-level.ts           # 反应级别
├── allowed-updates.ts          # 允许的更新
├── group-access.ts             # 群组访问
├── dm-access.ts                # 私聊访问
├── bot-access.ts               # 机器人访问
├── audit.ts                    # 审计
├── group-migration.ts          # 群组迁移
├── network-config.ts           # 网络配置
├── conversation-route.ts       # 会话路由
├── draft-*.ts                  # 草稿处理
├── sent-message-cache.ts       # 已发送消息缓存
├── sendchataction-*.ts         # 发送动作
├── target-writeback.ts         # 目标回写
├── api-logging.ts              # API 日志
├── reasoning-lane-*.ts         # 推理通道
└── *.test.ts                   # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
