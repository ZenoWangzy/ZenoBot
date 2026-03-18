[根目录](../../CLAUDE.md) > [src](../) > **shared**

# Shared

## 模块职责

Shared 模块包含跨模块共享的类型和工具，包括：

1. **共享类型** - 跨模块使用的公共类型
2. **配置工具** - 配置评估和 UI 提示
3. **聊天模型** - 聊天消息的共享模型
4. **设备认证** - 设备认证的共享逻辑

## 入口与启动

- 按需导入各模块

## 对外接口

### 核心类型

| 模块 | 职责 |
|------|------|
| `chat-message-content.ts` | 聊天消息内容 |
| `chat-content.ts` | 聊天内容 |
| `chat-envelope.ts` | 聊天信封 |
| `device-auth.ts` | 设备认证 |

### 配置相关

| 模块 | 职责 |
|------|------|
| `config-eval.ts` | 配置评估 |
| `config-ui-hints-types.ts` | UI 提示类型 |

### 其他

| 模块 | 职责 |
|------|------|
| `assistant-identity-values.ts` | 助手身份 |
| `avatar-policy.ts` | 头像策略 |

## 关键依赖与配置

### 使用方式

```typescript
import type { ChatMessageContent } from '../shared/chat-message-content';
import { evalConfig } from '../shared/config-eval';
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖配置评估、头像策略

## 相关文件清单

```
src/shared/
├── chat-message-content.ts        # 消息内容
├── chat-content.ts                # 聊天内容
├── chat-envelope.ts               # 聊天信封
├── device-auth.ts                 # 设备认证
├── config-eval.ts                 # 配置评估
├── config-ui-hints-types.ts       # UI 提示
├── assistant-identity-values.ts   # 助手身份
├── avatar-policy.ts               # 头像策略
└── *.test.ts                      # 测试
```

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
