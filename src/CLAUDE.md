[根目录](../CLAUDE.md) > **src**

# src 模块文档

## 模块职责

`src/` 是 OpenClaw 的核心源代码目录，包含所有 TypeScript 实现的核心功能，包括：

- AI 代理运行时（Pi Agent 嵌入式）
- WebSocket 控制平面（Gateway）
- 消息渠道集成系统
- CLI 命令实现
- 配置管理系统
- 浏览器自动化服务
- 插件 SDK

## 入口与启动

### 主入口文件

- **`entry.ts`** - 主入口点，处理进程启动和参数规范化
- **`index.ts`** - 导出主要 API 和构建 CLI 程序

### 启动流程

```
openclaw.mjs
  ↓
entry.ts (规范化参数、抑制警告)
  ↓
cli/run-main.ts (解析 CLI 配置)
  ↓
cli/program/build-program.ts (构建 Commander 程序)
  ↓
commands/ (执行具体命令)
```

## 对外接口

### CLI 命令

- `agent` - 与 AI 助手交互
- `gateway` - 启动/管理 Gateway 服务
- `configure` / `onboard` - 配置向导
- `channels` - 管理消息渠道
- `agents` - 管理代理配置
- `models` - 管理模型配置
- `doctor` - 诊断和修复
- `dashboard` - 启动控制面板

### Gateway WebSocket API

- **端口**: 默认 18789
- **协议**: WebSocket
- **主要方法**:
  - `chat.*` - 聊天相关
  - `agent.*` - 代理控制
  - `config.*` - 配置管理
  - `channels.*` - 渠道管理
  - `browser.*` - 浏览器控制
  - `nodes.*` - 节点管理

## 关键依赖与配置

### 核心依赖

- `@mariozechner/pi-agent-core` - Pi Agent 核心
- `@mariozechner/pi-ai` - Pi AI 集成
- `@agentclientprotocol/sdk` - ACP SDK
- `grammy` - Telegram SDK
- `@whiskeysockets/baileys` - WhatsApp SDK
- `@slack/bolt` - Slack SDK
- `discord-api-types` - Discord 类型

### 配置文件

- `tsconfig.json` - TypeScript 配置
- `vitest.config.ts` - 单元测试配置
- `vitest.e2e.config.ts` - E2E 测试配置
- `vitest.live.config.ts` - 实时测试配置

## 数据模型

### 主要类型定义

- `src/config/types.*.ts` - 配置类型
- `src/gateway/protocol/schema/` - Gateway 协议 schema
- `src/channels/plugins/types.*.ts` - 渠道插件类型

### 关键数据结构

- `AgentConfig` - 代理配置
- `ChannelConfig` - 渠道配置
- `SessionStore` - 会话存储
- `GatewayProtocol` - Gateway 协议

## 测试与质量

### 测试框架

- **单元测试**: Vitest
- **覆盖率阈值**:
  - 行覆盖率: 70%
  - 函数覆盖率: 70%
  - 分支覆盖率: 55%
  - 语句覆盖率: 70%

### 质量工具

- **格式化**: oxfmt
- **Lint**: oxlint (类型感知)
- **类型检查**: tsc

### 测试组织

```
src/
├── agents/
│   ├── *.ts
│   └── *.test.ts
├── gateway/
│   ├── *.ts
│   └── *.test.ts
└── ...
```

## 子模块索引

| 子模块     | 路径            | 职责                  |
| ---------- | --------------- | --------------------- |
| agents     | src/agents/     | AI 代理运行时         |
| gateway    | src/gateway/    | WebSocket 控制平面    |
| channels   | src/channels/   | 消息渠道集成          |
| commands   | src/commands/   | CLI 命令              |
| config     | src/config/     | 配置管理              |
| browser    | src/browser/    | 浏览器自动化          |
| cli        | src/cli/        | 命令行界面            |
| wizard     | src/wizard/     | 向导流程              |
| acp        | src/acp/        | Agent Client Protocol |
| plugin-sdk | src/plugin-sdk/ | 插件开发 SDK          |

## 常见问题 (FAQ)

### Q: 如何添加新的 CLI 命令？

在 `src/cli/program/command-registry.ts` 中注册新命令。

### Q: 如何添加新的消息渠道？

在 `src/channels/plugins/` 中创建新的渠道插件，并实现必要的接口。

### Q: 如何调试 Gateway？

使用 `--verbose` 标志启动 Gateway，或使用 `pnpm gateway:dev`。

### Q: 配置文件在哪里？

默认位置：`~/.openclaw/config.yaml`

## 相关文件清单

### 核心入口

- `src/entry.ts`
- `src/index.ts`
- `src/runtime.ts`

### 配置

- `tsconfig.json`
- `package.json`
- `vitest.config.ts`
- `vitest.e2e.config.ts`
- `vitest.live.config.ts`

### 工具脚本

- `scripts/run-node.mjs`
- `scripts/watch-node.mjs`
- `scripts/ui.js`

## 变更记录 (Changelog)

### 2026-02-11 00:58:28

- 初始化 src 模块文档
- 完成模块结构分析
- 识别主要子模块和入口点
