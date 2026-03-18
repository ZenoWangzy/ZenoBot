[根目录](../../CLAUDE.md) > [src](../) > **config**

# Configuration

## 模块职责

Configuration 模块负责 OpenClaw 的所有配置管理，包括：

1. **配置加载** - 从文件和环境变量加载配置
2. **配置验证** - 使用 Zod 模式验证配置
3. **配置合并** - 合并多源配置
4. **迁移** - 旧版本配置迁移
5. **类型定义** - 配置类型和模式

## 入口与启动

- 主入口：`config.ts` - `loadConfig()`
- 路径解析：`paths.ts` - 配置文件路径
- 会话配置：`sessions.ts` - 会话存储配置

## 对外接口

### 核心

| 模块 | 职责 |
|------|------|
| `config.ts` | 配置加载 |
| `merge-config.ts` | 配置合并 |
| `merge-patch.ts` | JSON 合并补丁 |
| `paths.ts` | 路径解析 |
| `config-paths.ts` | 配置路径 |

### 类型定义

| 模块 | 职责 |
|------|------|
| `types.auth.ts` | 认证类型 |
| `types.agents-shared.ts` | 代理类型 |
| `types.skills.ts` | 技能类型 |
| `types.queue.ts` | 队列类型 |
| `types.memory.ts` | 内存类型 |
| `types.channel-messaging-common.ts` | 通道消息类型 |
| `types.installs.ts` | 安装类型 |
| `types.approvals.ts` | 审批类型 |

### Zod 模式

| 模块 | 职责 |
|------|------|
| `zod-schema.channels.ts` | 通道模式 |
| `zod-schema.providers.ts` | 提供者模式 |
| `zod-schema.hooks.ts` | 钩子模式 |
| `zod-schema.auth.ts` | 认证模式 |
| `zod-schema.allowdeny.ts` | 允许/拒绝模式 |
| `zod-schema.sensitive.ts` | 敏感数据模式 |
| `zod-schema.agent-model.ts` | 代理模型模式 |
| `zod-schema.logging-levels.ts` | 日志级别模式 |

### 会话

| 模块 | 职责 |
|------|------|
| `sessions.ts` | 会话配置 |
| `sessions/artifacts.ts` | 会话工件 |
| `sessions/delivery-info.ts` | 投递信息 |

### 迁移

| 模块 | 职责 |
|------|------|
| `legacy.migrations.ts` | 旧版迁移 |
| `legacy.migrations.part-2.ts` | 迁移第二部分 |

## 关键依赖与配置

### 配置文件位置

- 主配置：`~/.openclaw/config.json`
- 代理配置：`~/.openclaw/agents/<agent-id>/config.json`
- 会话存储：`~/.openclaw/sessions/`

### 配置合并顺序

1. 默认值
2. 全局配置文件
3. 代理配置文件
4. 环境变量
5. 命令行参数

## 数据模型

### 配置结构

```typescript
interface Config {
  agents: AgentConfig[];
  telegram?: TelegramConfig;
  discord?: DiscordConfig;
  slack?: SlackConfig;
  // ... 其他通道配置
}
```

## 相关文件清单

```
src/config/
├── config.ts                # 配置加载
├── merge-config.ts          # 合并
├── merge-patch.ts           # 补丁
├── paths.ts                 # 路径
├── config-paths.ts          # 配置路径
├── sessions.ts              # 会话
├── sessions/                # 会话子模块
├── types.*.ts               # 类型定义
├── zod-schema.*.ts          # Zod 模式
├── legacy.migrations*.ts    # 迁移
├── commands.ts              # 命令配置
├── bindings.ts              # 绑定
├── agent-dirs.ts            # 代理目录
├── channel-capabilities.ts  # 通道能力
├── runtime-group-policy.ts  # 组策略
├── allowed-values.ts        # 允许值
├── byte-size.ts             # 字节大小
├── cache-utils.ts           # 缓存工具
├── port-defaults.ts         # 端口默认值
├── version.ts               # 版本
├── includes.ts              # 包含
├── env-preserve.ts          # 环境保留
├── prototype-keys.ts        # 原型键
├── plugins-allowlist.ts     # 插件白名单
├── telegram-custom-commands.ts # Telegram 命令
├── backup-rotation.ts       # 备份轮换
├── model-input.ts           # 模型输入
├── group-policy.test.ts     # 组策略测试
├── test-helpers.ts          # 测试辅助
└── *.test.ts                # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
