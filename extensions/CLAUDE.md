[根目录](../CLAUDE.md) > **extensions**

# extensions 模块文档

## 模块职责

`extensions/` 包含 OpenClaw 的扩展插件，每个扩展提供与第三方服务的集成，主要是消息渠道如 BlueBubbles (iMessage)、Discord、飞书、Google Chat 等。

## 入口与启动

### 扩展加载

- **加载入口**: `src/channels/plugins/load.ts`
- **自动发现**: 扫描 `extensions/` 目录下的 `openclaw.plugin.json`
- **初始化**: 通过 `index.ts` 导出的函数

### 扩展结构

```
extensions/{name}/
├── openclaw.plugin.json    # 插件元数据
├── package.json            # NPM 包配置
├── index.ts                # 主入口
├── README.md               # 文档
└── src/                    # 源代码
    ├── runtime.ts          # 运行时
    ├── channel.ts          # 渠道实现
    ├── config-schema.ts    # 配置 schema
    └── ...
```

## 对外接口

### 标准接口

每个扩展必须实现：

- `createChannel()` - 创建渠道实例
- `onboarding` - 入向消息处理
- `outbound` - 出向消息处理
- `configSchema` - 配置 schema

### BlueBubbles 扩展

- **功能**: iMessage 集成（推荐方式）
- **协议**: BlueBubbles Server API
- **支持**: 群组、媒体、反应、状态

### Discord 扩展

- **功能**: Discord 机器人集成
- **协议**: Discord API
- **支持**: Slash 命令、群组、DM

### 飞书扩展

- **功能**: 飞书机器人集成
- **协议**: 飞书开放平台 API
- **支持**: 消息、卡片、机器人

### Google Chat 扩展

- **功能**: Google Chat 集成
- **协议**: Google Chat API
- **支持**: DM、群组、卡片

## 关键依赖与配置

### 通用依赖

- Zod - 配置 schema 验证
- Express - HTTP 服务器
- ws - WebSocket 客户端

### 特定依赖

- **BlueBubbles**: 无额外 SDK（使用 fetch）
- **Discord**: discord-api-types
- **飞书**: @larksuiteoapi/node-sdk
- **Google Chat**: googleapis

### 配置文件

每个扩展需要 `openclaw.plugin.json`：

```json
{
  "name": "extension-name",
  "version": "1.0.0",
  "description": "Extension description",
  "main": "index.ts",
  "type": "channel",
  "configSchema": "./src/config-schema.ts"
}
```

## 数据模型

### 通用类型

- `ChannelConfig` - 渠道配置基类
- `PluginRuntime` - 插件运行时
- `MessageHandler` - 消息处理器

### 扩展特定类型

每个扩展定义自己的消息类型和配置 schema。

## 测试与质量

### 测试位置

- `extensions/*/*.test.ts`
- `extensions/*/src/*.test.ts`

### 测试覆盖

- BlueBubbles: 较完整测试覆盖
- 其他扩展: 有限测试覆盖

## 子模块索引

| 扩展名                  | 路径                                | 类型     | 描述             |
| ----------------------- | ----------------------------------- | -------- | ---------------- |
| bluebubbles             | extensions/bluebubbles/             | 消息渠道 | iMessage 集成    |
| discord                 | extensions/discord/                 | 消息渠道 | Discord 集成     |
| feishu                  | extensions/feishu/                  | 消息渠道 | 飞书集成         |
| googlechat              | extensions/googlechat/              | 消息渠道 | Google Chat 集成 |
| google-antigravity-auth | extensions/google-antigravity-auth/ | 认证     | Google 认证      |
| google-gemini-cli-auth  | extensions/google-gemini-cli-auth/  | 认证     | Gemini CLI 认证  |
| copilot-proxy           | extensions/copilot-proxy/           | 代理     | Copilot 代理     |

## 常见问题 (FAQ)

### Q: 如何创建新扩展？

1. 在 `extensions/` 下创建新目录
2. 添加 `openclaw.plugin.json`
3. 实现 `index.ts` 中的必要接口
4. 添加配置 schema

### Q: 如何调试扩展？

使用 `openclaw channels logs {extension-name}` 查看日志。

### Q: 扩展如何与 Gateway 通信？

通过 WebSocket 连接，使用 Gateway 协议。

## 相关文件清单

### 核心

- `src/channels/plugins/index.ts`
- `src/channels/plugins/load.ts`
- `src/channels/plugins/catalog.ts`

### 扩展列表

- `extensions/bluebubbles/`
- `extensions/discord/`
- `extensions/feishu/`
- `extensions/googlechat/`

## 变更记录 (Changelog)

### 2026-02-11 00:58:28

- 初始化 extensions 模块文档
- 识别主要扩展和接口
