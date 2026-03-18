[根目录](../../../CLAUDE.md) > [src](../../) > [gateway](../) > **server-methods**

# Gateway Server Methods

## 模块职责

Gateway Server Methods 实现了 WebSocket 网关服务器的所有 RPC 方法处理程序。这是客户端（移动应用、Web UI、桌面应用）与后端核心功能之间的主要接口层。

## 入口与启动

- 主入口：由 `src/gateway/server.ts` 动态加载和注册
- 方法类型定义：`types.ts`

## 对外接口

### 核心方法模块

| 模块 | 职责 |
|------|------|
| `agent.ts` | AI 代理执行和会话管理 |
| `agents.ts` | 多代理配置和绑定 |
| `chat.ts` | 聊天消息处理和流式响应 |
| `config.ts` | 配置读写 |
| `connect.ts` | 连接和认证 |
| `devices.ts` | 设备管理 |
| `doctor.ts` | 诊断和修复工具 |
| `health.ts` | 健康检查和探针 |
| `models.ts` | 模型目录和选择 |
| `nodes.ts` | 节点调用和工具执行 |
| `sessions.ts` | 会话持久化和管理 |
| `skills.ts` | 技能配置 |
| `tools-catalog.ts` | 工具目录 |
| `usage.ts` | 使用统计 |
| `wizard.ts` | 引导式设置向导 |

### 通道相关

| 模块 | 职责 |
|------|------|
| `channels.ts` | 通道状态和配置 |
| `send.ts` | 消息发送 |

### 系统操作

| 模块 | 职责 |
|------|------|
| `cron.ts` | 定时任务 |
| `exec-approval.ts` | 执行审批 |
| `logs.ts` | 日志访问 |
| `push.ts` | 推送通知 |
| `secrets.ts` | 密钥管理 |
| `system.ts` | 系统操作 |
| `update.ts` | 更新检查 |

## 关键依赖与配置

- 依赖 `src/gateway/server.ts` 进行服务器初始化
- 使用 `src/config/` 中的配置模块
- 调用 `src/plugins/runtime/` 提供的插件运行时

## 数据模型

### Pi Session Transcripts

**重要**：Pi 会话转录是 `parentId` 链/DAG 结构。

- **禁止**：直接通过原始 JSONL 写入追加 Pi `type: "message"` 条目
- **原因**：缺少 `parentId` 可能断开叶子路径，破坏压缩和历史记录
- **正确做法**：始终通过 `SessionManager.appendMessage(...)` 或使用它的包装器写入转录消息

## 测试与质量

- 测试文件命名：`*.test.ts`
- 测试辅助：`chat.test-helpers.ts`
- 覆盖的方法：agent、chat、doctor、nodes、skills、tools-catalog、update、usage

## 常见问题 (FAQ)

### 如何添加新的 RPC 方法？

1. 在 `types.ts` 中定义方法类型
2. 创建新的方法处理文件
3. 在服务器初始化时注册方法

### 为什么直接写入 JSONL 会破坏会话？

Pi 的会话历史依赖于 `parentId` 链来维护消息顺序和压缩。直接写入会跳过父链接设置，导致历史断开。

## 相关文件清单

```
src/gateway/server-methods/
├── agent.ts              # 代理执行
├── agents.ts             # 多代理管理
├── browser.ts            # 浏览器控制
├── channels.ts           # 通道管理
├── chat.ts               # 聊天处理
├── config.ts             # 配置
├── connect.ts            # 连接
├── cron.ts               # 定时任务
├── devices.ts            # 设备
├── doctor.ts             # 诊断
├── exec-approval.ts      # 执行审批
├── exec-approvals.ts     # 审批管理
├── health.ts             # 健康检查
├── logs.ts               # 日志
├── models.ts             # 模型
├── nodes.ts              # 节点/工具
├── push.ts               # 推送
├── secrets.ts            # 密钥
├── send.ts               # 发送
├── sessions.ts           # 会话
├── skills.ts             # 技能
├── system.ts             # 系统
├── talk.ts               # 语音通话
├── tools-catalog.ts      # 工具目录
├── tts.ts                # 文本转语音
├── update.ts             # 更新
├── usage.ts              # 使用统计
├── validation.ts         # 验证
├── voicewake.ts          # 语音唤醒
├── web.ts                # Web 相关
├── wizard.ts             # 向导
└── types.ts              # 类型定义
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
