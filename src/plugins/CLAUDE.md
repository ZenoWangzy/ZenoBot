[根目录](../../CLAUDE.md) > [src](../) > **plugins**

# Plugins System

## 模块职责

Plugins 模块实现了 OpenClaw 的插件系统，包括：

1. **插件发现与加载** - 扫描和加载本地及 npm 插件
2. **运行时环境** - 为插件提供安全的运行时 API
3. **钩子系统** - 允许插件在关键点注入行为
4. **通道插件** - 支持通过插件扩展消息通道
5. **工具注册** - 允许插件注册 AI 工具

## 入口与启动

- 运行时入口：`runtime/index.ts` - `createPluginRuntime()`
- 加载器：`loader.ts` - 插件加载和验证
- 发现：`discovery.ts` - 插件发现

## 对外接口

### 核心

| 模块 | 职责 |
|------|------|
| `loader.ts` | 插件加载 |
| `discovery.ts` | 插件发现 |
| `registry.ts` | 插件注册表 |
| `manifest.ts` | 清单解析 |
| `runtime.ts` | 运行时管理 |

### 运行时 API

| 模块 | 职责 |
|------|------|
| `runtime/index.ts` | 运行时入口 |
| `runtime/runtime-channel.ts` | 通道 API |
| `runtime/runtime-config.ts` | 配置 API |
| `runtime/runtime-events.ts` | 事件 API |
| `runtime/runtime-logging.ts` | 日志 API |
| `runtime/runtime-media.ts` | 媒体 API |
| `runtime/runtime-system.ts` | 系统 API |
| `runtime/runtime-tools.ts` | 工具 API |
| `runtime/types.ts` | 运行时类型 |

### 钩子

| 模块 | 职责 |
|------|------|
| `hooks.ts` | 钩子系统 |
| `hook-runner-global.ts` | 全局钩子运行器 |
| `wired-hooks-*.ts` | 已连接的钩子实现 |

### 安装与管理

| 模块 | 职责 |
|------|------|
| `install.ts` | 插件安装 |
| `installs.ts` | 安装管理 |
| `uninstall.ts` | 插件卸载 |
| `enable.ts` | 启用/禁用 |
| `update.ts` | 更新 |

### HTTP 与服务

| 模块 | 职责 |
|------|------|
| `http-registry.ts` | HTTP 路由注册 |
| `services.ts` | 服务管理 |
| `commands.ts` | 命令注册 |

## 关键依赖与配置

### 插件配置

插件通过 `package.json` 中的 `openclaw` 字段配置：

```json
{
  "name": "@openclaw/example",
  "openclaw": {
    "extensions": ["./index.ts"],
    "channel": {
      "id": "example",
      "label": "Example Channel"
    },
    "install": {
      "npmSpec": "@openclaw/example",
      "localPath": "extensions/example"
    }
  }
}
```

### 插件运行时

插件运行时通过 `createPluginRuntime()` 创建，提供：

- `config` - 配置访问
- `channel` - 通道操作
- `media` - 媒体处理
- `tools` - 工具注册
- `events` - 事件订阅
- `logging` - 日志记录
- `system` - 系统操作
- `subagent` - 子代理运行（仅请求期间可用）

## 数据模型

### 插件类型

- `types.ts` - 核心插件类型
- `runtime/types-core.ts` - 核心运行时类型
- `runtime/types-channel.ts` - 通道运行时类型

### 配置模式

- `config-schema.ts` - 配置模式
- `config-state.ts` - 配置状态

## 测试与质量

- 测试覆盖：loader、discovery、hooks、install、runtime、http-registry
- 测试辅助：`hooks.test-helpers.ts`

## 常见问题 (FAQ)

### 如何创建新插件？

1. 在 `extensions/` 目录创建新包
2. 添加 `package.json` 和 `openclaw` 配置
3. 实现插件入口（`index.ts`）
4. 使用运行时 API 注册功能

### 插件如何注册工具？

通过 `runtime.tools.registerTool()` 方法注册工具，工具会自动出现在 AI 的工具目录中。

### 插件依赖应该放在哪里？

插件专用依赖放在插件的 `package.json` 的 `dependencies` 中。不要将它们添加到根 `package.json`。避免在 `dependencies` 中使用 `workspace:*`。

## 相关文件清单

```
src/plugins/
├── loader.ts                # 插件加载
├── discovery.ts             # 插件发现
├── registry.ts              # 注册表
├── manifest.ts              # 清单
├── runtime.ts               # 运行时管理
├── types.ts                 # 类型
├── hooks.ts                 # 钩子系统
├── hook-runner-global.ts    # 全局钩子
├── install.ts               # 安装
├── installs.ts              # 安装管理
├── uninstall.ts             # 卸载
├── enable.ts                # 启用/禁用
├── update.ts                # 更新
├── cli.ts                   # CLI
├── commands.ts              # 命令
├── http-registry.ts         # HTTP 注册
├── services.ts              # 服务
├── tools.ts                 # 工具
├── slots.ts                 # 插槽
├── status.ts                # 状态
├── providers.ts             # 提供者
├── schema-validator.ts      # 模式验证
├── toggle-config.ts         # 配置切换
├── bundled-*.ts             # 打包源
├── config-*.ts              # 配置
├── path-safety.ts           # 路径安全
├── http-*.ts                # HTTP 相关
└── runtime/                 # 运行时 API
    ├── index.ts             # 入口
    ├── types.ts             # 类型
    ├── types-*.ts           # 类型定义
    ├── runtime-*.ts         # 运行时模块
    └── *.test.ts            # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
