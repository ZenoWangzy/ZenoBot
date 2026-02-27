[根目录](../../CLAUDE.md) > **src** > **commands**

---

# Commands 模块

> CLI 命令行接口

---

## 变更记录 (Changelog)

### 2026-02-16
- 更新面包屑导航

### 2026-02-11
- 创建模块文档

---

## 模块职责

`src/commands/` 包含所有 CLI 命令的实现，提供与 OpenClaw 交互的命令行界面。

### 主要命令类别

| 类别 | 命令 | 描述 |
|------|------|------|
| Agent | `openclaw agent` | 直接与 AI 助手对话 |
| Channels | `openclaw channels` | 管理消息渠道 |
| Gateway | `openclaw gateway` | 启动/管理网关 |
| Configure | `openclaw configure` | 配置向导 |
| Doctor | `openclaw doctor` | 诊断工具 |
| Devices | `openclaw devices` | 管理移动节点 |
| Onboard | `openclaw onboard` | 新用户入门向导 |
| Models | `openclaw models` | 模型管理 |
| Sessions | `openclaw sessions` | 会话管理 |
| Sandbox | `openclaw sandbox` | 沙箱管理 |

---

## 入口与启动

### 主要入口
- `src/entry.ts` - CLI 入口
- `openclaw.mjs` - 可执行入口
- `src/cli/run-main.ts` - CLI 主运行逻辑

### 关键文件

| 文件 | 描述 |
|------|------|
| `src/commands/agent.ts` | agent 命令 |
| `src/commands/channels.ts` | channels 命令 |
| `src/commands/gateway-status.ts` | gateway 相关命令 |
| `src/commands/configure.*.ts` | configure 命令系列 |
| `src/commands/doctor.ts` | doctor 诊断命令 |
| `src/commands/onboard.ts` | 入门向导 |
| `src/commands/models/` | 模型管理命令 |
| `src/commands/sandbox.ts` | 沙箱管理命令 |

---

## 对外接口

### Agent 命令
```bash
openclaw agent --message "你好"
openclaw agent --thinking high
openclaw agent --via-gateway
```

### Channels 命令
```bash
openclaw channels add telegram
openclaw channels list
openclaw channels remove <id>
openclaw channels status
```

### Gateway 命令
```bash
openclaw gateway --port 18789
openclaw gateway status
```

### Configure 命令
```bash
openclaw configure
openclaw configure gateway
openclaw configure channels
openclaw configure daemon
```

### Doctor 命令
```bash
openclaw doctor
openclaw doctor auth
openclaw doctor gateway
openclaw doctor sandbox
```

### Onboard 命令
```bash
openclaw onboard
openclaw onboard --install-daemon
openclaw onboard --non-interactive
```

### Models 命令
```bash
openclaw models list
openclaw models status
openclaw models set <model-id>
```

### Sandbox 命令
```bash
openclaw sandbox list
openclaw sandbox create
openclaw sandbox prune
```

---

## 关键依赖与配置

### 外部依赖
```json
{
  "commander": "^14.0.3",
  "@clack/prompts": "^1.0.0",
  "chalk": "^5.6.2"
}
```

---

## 子目录结构

```
src/commands/
├── agent/                  # agent 命令子模块
│   ├── delivery.ts
│   ├── run-context.ts
│   └── session.ts
├── channels/               # channels 命令子模块
│   ├── add.ts
│   ├── list.ts
│   ├── remove.ts
│   ├── status.ts
│   └── capabilities.ts
├── models/                 # models 命令子模块
│   ├── list.ts
│   ├── set.ts
│   ├── scan.ts
│   └── auth.ts
├── onboard-non-interactive/  # 非交互式入门
│   ├── local/
│   └── remote.ts
├── onboarding/             # 入门引导
│   ├── plugin-install.ts
│   └── registry.ts
├── status-all/             # 状态汇总
│   ├── agents.ts
│   ├── channels.ts
│   ├── gateway.ts
│   └── diagnosis.ts
├── agent.ts                # agent 命令
├── channels.ts             # channels 命令
├── gateway-status.ts       # gateway 状态
├── configure.*.ts          # configure 命令系列
├── doctor*.ts              # doctor 诊断系列
├── onboard*.ts             # 入门系列
├── models.ts               # models 命令
├── sandbox.ts              # sandbox 命令
├── sessions.ts             # sessions 命令
├── health.ts               # health 命令
├── reset.ts                # reset 命令
└── uninstall.ts            # uninstall 命令
```

---

## 测试与质量

### 测试文件
- 各命令目录下的 `*.test.ts` 文件

### 运行测试
```bash
vitest run src/commands
```
