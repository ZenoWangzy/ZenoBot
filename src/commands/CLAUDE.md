[根目录](../../CLAUDE.md) > [src](../) > **commands**

# Commands

## 模块职责

Commands 模块实现了 OpenClaw CLI 的所有命令，包括：

1. **核心命令** - gateway、config、channels 等
2. **代理命令** - agent、message、sessions 等
3. **系统命令** - doctor、update、version 等
4. **工具命令** - nodes、tools、browser 等

## 入口与启动

- 命令由 `src/cli/program.ts` 注册
- 每个命令模块导出 `register*Command()` 函数

## 对外接口

### 核心命令

| 模块 | 命令 | 描述 |
|------|------|------|
| `gateway.ts` | `gateway run` | 启动网关服务器 |
| `config.ts` | `config get/set` | 配置管理 |
| `channels.ts` | `channels status` | 通道状态 |
| `devices.ts` | `devices list` | 设备管理 |

### 代理命令

| 模块 | 命令 | 描述 |
|------|------|------|
| `agent.ts` | `agent` | 代理操作 |
| `message.ts` | `message send` | 发送消息 |
| `sessions.ts` | `sessions` | 会话管理 |

### 系统命令

| 模块 | 命令 | 描述 |
|------|------|------|
| `doctor.ts` | `doctor` | 诊断修复 |
| `update.ts` | `update` | 更新检查 |
| `version.ts` | `--version` | 版本信息 |

### 工具命令

| 模块 | 命令 | 描述 |
|------|------|------|
| `nodes.ts` | `nodes` | 节点操作 |
| `tools.ts` | `tools` | 工具管理 |
| `browser.ts` | `browser` | 浏览器控制 |

### 其他命令

| 模块 | 命令 | 描述 |
|------|------|------|
| `pairing.ts` | `pairing` | 设备配对 |
| `cron.ts` | `cron` | 定时任务 |
| `logs.ts` | `logs` | 日志查看 |
| `wizard.ts` | `wizard` | 设置向导 |

## 关键依赖与配置

### 依赖

- `src/cli/` - CLI 框架
- `src/gateway/` - 网关功能
- `src/config/` - 配置管理

## 相关文件清单

```
src/commands/
├── gateway.ts              # 网关命令
├── config.ts               # 配置命令
├── channels.ts             # 通道命令
├── devices.ts              # 设备命令
├── agent.ts                # 代理命令
├── message.ts              # 消息命令
├── sessions.ts             # 会话命令
├── doctor.ts               # 诊断命令
├── update.ts               # 更新命令
├── version.ts              # 版本命令
├── nodes.ts                # 节点命令
├── tools.ts                # 工具命令
├── browser.ts              # 浏览器命令
├── pairing.ts              # 配对命令
├── cron.ts                 # 定时任务命令
├── logs.ts                 # 日志命令
├── wizard.ts               # 向导命令
├── plugins.ts              # 插件命令
├── completion.ts           # 补全命令
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
