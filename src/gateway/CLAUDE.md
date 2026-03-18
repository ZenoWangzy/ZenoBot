[根目录](../../CLAUDE.md) > [src](../) > **gateway**

# Gateway

## 模块职责

Gateway 模块是 OpenClaw 的核心服务器组件，负责：

1. **WebSocket 服务器** - 处理来自客户端（移动应用、Web UI、桌面应用）的 WebSocket 连接
2. **协议处理** - 实现客户端-服务器通信协议
3. **会话管理** - 管理 AI 会话的创建、存储和检索
4. **认证授权** - 设备配对、令牌验证、访问控制
5. **RPC 方法分发** - 将客户端请求路由到对应的服务器方法

## 入口与启动

- 主入口：`server.ts` -> `server.impl.js`
- 启动函数：`startGatewayServer(options)`
- 通过 `src/cli/gateway-cli.ts` 中的 CLI 命令启动

## 对外接口

### 服务器核心

| 模块 | 职责 |
|------|------|
| `server.ts` | 服务器导出 |
| `server.impl.ts` | 服务器实现 |
| `server-shared.ts` | 共享服务器逻辑 |
| `server-constants.ts` | 服务器常量 |

### 连接管理

| 模块 | 职责 |
|------|------|
| `server/ws-connection/` | WebSocket 连接处理 |
| `auth-rate-limit.ts` | 认证速率限制 |
| `device-auth.test.ts` | 设备认证 |

### 协议

| 模块 | 职责 |
|------|------|
| `protocol/schema/` | 协议模式定义 |
| `protocol/client-info.ts` | 客户端信息 |
| `server-methods/` | RPC 方法实现（见 [server-methods/CLAUDE.md](./server-methods/CLAUDE.md)）|

### 会话与代理

| 模块 | 职责 |
|------|------|
| `agent-prompt.ts` | 代理提示构建 |
| `chat-abort.ts` | 聊天中止 |
| `chat-attachments.ts` | 聊天附件 |
| `sessions-resolve.ts` | 会话解析 |

### 发现与网络

| 模块 | 职责 |
|------|------|
| `server-discovery.ts` | 服务器发现（mDNS/Bonjour） |
| `server-tailscale.ts` | Tailscale 集成 |
| `server-node-events-types.ts` | 节点事件类型 |

## 关键依赖与配置

### 外部依赖

- `ws` - WebSocket 服务器
- `@homebridge/ciao` - mDNS/Bonjour 服务发现
- Express - HTTP 端点

### 内部依赖

- `src/config/` - 配置管理
- `src/plugins/runtime/` - 插件运行时
- `src/agents/` - AI 代理运行时
- `src/infra/` - 基础设施（TLS、端口、网络）

## 数据模型

### 协议模式

- `protocol/schema/frames.ts` - 通信帧
- `protocol/schema/sessions.ts` - 会话数据
- `protocol/schema/devices.ts` - 设备信息
- `protocol/schema/agents-models-skills.ts` - 代理、模型、技能
- `protocol/schema/wizard.ts` - 向导数据
- `protocol/schema/push.ts` - 推送通知

### 会话数据

会话存储在 `~/.openclaw/sessions/` 目录下，使用 JSONL 格式。

## 测试与质量

### 测试类型

- 单元测试：`*.test.ts`
- E2E 测试：`server.*.test.ts`
- 测试辅助：`test-helpers.ts`、`session-preview.test-helpers.ts`

### 测试覆盖

- 服务器启动和关闭
- WebSocket 连接和认证
- 会话管理
- 配置应用
- 健康检查
- 工具目录

## 常见问题 (FAQ)

### 如何调试 Gateway 问题？

1. 检查日志：`tail -n 120 /tmp/openclaw-gateway.log`
2. 验证端口：`ss -ltnp | rg 18789`
3. 运行诊断：`openclaw channels status --probe`

### 如何重启 Gateway？

- macOS：通过 OpenClaw Mac 应用或 `scripts/restart-mac.sh`
- Linux：`pkill -9 -f openclaw-gateway || true; nohup openclaw gateway run ... &`

### Gateway 当前如何运行？

Gateway 当前仅作为菜单栏应用运行，没有单独的 LaunchAgent/helper 标签安装。调试时通过应用启动/停止，而不是 ad-hoc tmux 会话。

## 相关文件清单

```
src/gateway/
├── server.ts                    # 服务器导出
├── server-*.ts                  # 服务器组件
├── protocol/                    # 协议定义
│   ├── schema/                  # 模式定义
│   └── client-info.ts           # 客户端信息
├── server-methods/              # RPC 方法（见 CLAUDE.md）
├── server/                      # 服务器内部
│   ├── close-reason.ts          # 关闭原因
│   ├── tls.ts                   # TLS 配置
│   ├── ws-connection/           # WebSocket 连接
│   └── ws-types.ts              # WebSocket 类型
├── agent-*.ts                   # 代理相关
├── chat-*.ts                    # 聊天相关
├── *-rate-limit.ts              # 速率限制
├── ws-logging.ts                # WebSocket 日志
├── events.ts                    # 事件定义
├── hooks*.ts                    # 钩子
├── role-policy.ts               # 角色策略
├── canvas-capability.ts         # 画布能力
├── control-*.ts                 # 控制平面
├── exec-approval-manager.ts     # 执行审批
├── http-*.ts                    # HTTP 辅助
├── probe.ts                     # 探针
└── test-helpers.ts              # 测试辅助
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
