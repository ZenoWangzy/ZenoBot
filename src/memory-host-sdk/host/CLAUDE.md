[根目录](../../CLAUDE.md) > [src](../) > **memory**

# Memory

## 模块职责

Memory 模块负责 AI 的长期记忆功能，包括：

1. **记忆存储** - 存储和检索对话记忆
2. **向量嵌入** - 将记忆转换为向量表示
3. **语义搜索** - 基于相似度搜索相关记忆
4. **记忆压缩** - 压缩和总结长期记忆

## 入口与启动

- 主入口：`index.ts`
- 记忆后端可通过插件扩展（如 LanceDB）

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 记忆导出 |
| `types.ts` | 记忆类型定义 |
| `store.ts` | 记忆存储 |
| `embeddings.ts` | 向量嵌入 |

## 关键依赖与配置

### 记忆后端

- 默认：SQLite（sqlite-vec）
- 可选：LanceDB（通过 `extensions/memory-lancedb`）

### 配置

```json
{
  "memory": {
    "backend": "sqlite",
    "maxMemories": 1000,
    "similarityThreshold": 0.7
  }
}
```

## 数据模型

```typescript
interface Memory {
  id: string;
  content: string;
  embedding?: number[];
  metadata: MemoryMetadata;
  createdAt: number;
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖存储、检索、嵌入

## 相关文件清单

```
src/memory/
├── index.ts           # 记忆导出
├── types.ts           # 类型定义
├── store.ts           # 存储实现
├── embeddings.ts      # 嵌入处理
└── *.test.ts          # 测试
```

## 相关模块

- [extensions/memory-core](../../extensions/memory-core/) - 记忆核心插件
- [extensions/memory-lancedb](../../extensions/memory-lancedb/) - LanceDB 后端

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
