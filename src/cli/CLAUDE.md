[根目录](../../CLAUDE.md) > [src](../) > **cli**

# CLI (Command Line Interface)

## 模块职责

CLI 模块负责命令行界面的所有功能，包括命令解析、参数处理、用户交互和进度显示。

## 入口与启动

- 主入口：`program.ts` - 构建 Commander.js 程序实例
- CLI 入口：`openclaw.mjs` -> `dist/entry.js` -> `src/index.ts` -> `buildProgram()`

## 对外接口

### 核心 CLI 模块

| 模块 | 职责 |
|------|------|
| `program.ts` | 主程序构建和命令注册 |
| `program-context.ts` | 程序上下文和依赖注入 |
| `cli-utils.ts` | CLI 工具函数 |
| `prompt.ts` | 用户提示和确认 |
| `progress.ts` | 进度显示（使用 osc-progress + @clack/prompts） |

### 专用 CLI

| 模块 | 职责 |
|------|------|
| `gateway-cli.ts` | 网关命令 |
| `channels-cli.ts` | 通道管理 |
| `devices-cli.ts` | 设备管理 |
| `nodes-cli.ts` | 节点和工具调用 |
| `models-cli.ts` | 模型选择 |
| `sandbox-cli.ts` | 沙箱操作 |
| `daemon-cli.ts` | 守护进程管理 |
| `tui-cli.ts` | 终端 UI |
| `acp-cli.ts` | ACP 协议 |
| `browser-cli*.ts` | 浏览器自动化 |

## 关键依赖与配置

- Commander.js 用于命令解析
- `@clack/prompts` 用于交互式提示
- `osc-progress` 用于进度显示
- 依赖 `src/commands/` 中的命令实现

## 数据模型

- 命令选项定义在 `command-options.ts`
- 守护进程类型在 `daemon-cli/types.ts`
- 节点 CLI 类型在 `nodes-cli/types.ts`

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖：cli-utils、command-options、progress、prompt 等

## 常见问题 (FAQ)

### 如何添加新的 CLI 命令？

1. 在 `src/commands/` 中创建命令实现
2. 在 `src/cli/` 中创建对应的 CLI 注册代码
3. 在 `program.ts` 或相关注册函数中添加命令

### 进度显示应该如何实现？

使用 `src/cli/progress.ts` 提供的 `osc-progress` 和 `@clack/prompts` spinner，不要手写 spinner/进度条。

## 相关文件清单

```
src/cli/
├── program.ts              # 主程序
├── program-context.ts      # 程序上下文
├── cli-utils.ts            # 工具函数
├── prompt.ts               # 用户提示
├── progress.ts             # 进度显示
├── command-options.ts      # 命令选项
├── gateway-cli.ts          # 网关 CLI
├── channels-cli.ts         # 通道 CLI
├── devices-cli.ts          # 设备 CLI
├── nodes-cli.ts            # 节点 CLI
├── models-cli.ts           # 模型 CLI
├── sandbox-cli.ts          # 沙箱 CLI
├── daemon-cli.ts           # 守护进程 CLI
├── tui-cli.ts              # TUI CLI
├── acp-cli.ts              # ACP CLI
├── browser-cli*.ts         # 浏览器 CLI
├── gateway-rpc.ts          # Gateway RPC
├── pairing-cli.ts          # 配对 CLI
├── cron-cli.ts             # 定时任务 CLI
├── docs-cli.ts             # 文档 CLI
├── logs-cli*.ts            # 日志 CLI
├── directory-cli.ts        # 目录 CLI
├── profile.ts              # 配置文件
├── wait.ts                 # 等待工具
├── help-format.ts          # 帮助格式化
├── parse-*.ts              # 参数解析
└── respawn-policy.ts       # 重启策略
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
