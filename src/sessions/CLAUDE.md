[根目录](../../CLAUDE.md) > [src](../) > **sessions**

# Sessions

## 模块职责

Sessions 模块负责 AI 会话的管理，包括：

1. **会话存储** - 持久化会话数据到文件系统
2. **会话检索** - 加载和查询历史会话
3. **会话清理** - 清理过期或无效的会话
4. **会话元数据** - 管理会话的元信息

## 入口与启动

- 主入口：`index.ts`
- 会话目录：`~/.openclaw/sessions/`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 会话导出 |
| `types.ts` | 会话类型定义 |
| `store.ts` | 会话存储 |
| `manager.ts` | 会话管理器 |

## 关键依赖与配置

### 会话目录结构

```
~/.openclaw/sessions/
├── <session-id>/
│   ├── messages.jsonl    # 消息历史
│   ├── context.json      # 上下文状态
│   ├── metadata.json     # 元数据
│   └── config.json       # 会话配置
```

### 数据模型

```typescript
interface Session {
  id: string;
  createdAt: number;
  updatedAt: number;
  channelId: string;
  agentId?: string;
  model?: string;
  metadata: SessionMetadata;
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖会话 CRUD、清理、迁移

## 相关文件清单

```
src/sessions/
├── index.ts           # 会话导出
├── types.ts           # 类型定义
├── store.ts           # 存储实现
├── manager.ts         # 管理器
├── cleanup.ts         # 清理逻辑
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
