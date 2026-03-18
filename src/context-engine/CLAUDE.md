[根目录](../../CLAUDE.md) > [src](../) > **context-engine**

# Context Engine

## 模块职责

Context Engine 模块负责 AI 上下文的智能管理，包括：

1. **上下文构建** - 构建 AI 提示词的上下文
2. **上下文注册** - 注册可用的上下文提供者
3. **上下文优化** - 优化上下文以适应 token 限制
4. **遗留兼容** - 兼容旧的上下文格式

## 入口与启动

- 主入口：`index.ts`
- 初始化：`init.ts`
- 注册表：`registry.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 上下文引擎导出 |
| `init.ts` | 初始化逻辑 |
| `registry.ts` | 上下文提供者注册表 |
| `types.ts` | 类型定义 |
| `legacy.ts` | 遗留兼容 |

## 关键依赖与配置

### 配置

```json
{
  "contextEngine": {
    "enabled": true,
    "maxTokens": 128000,
    "priority": ["memory", "tools", "history"]
  }
}
```

### 上下文优先级

1. 系统提示
2. 工具定义
3. 记忆上下文
4. 对话历史

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖上下文构建、优化、注册

## 相关文件清单

```
src/context-engine/
├── index.ts                       # 上下文引擎导出
├── init.ts                        # 初始化
├── registry.ts                    # 注册表
├── types.ts                       # 类型定义
├── legacy.ts                      # 遗留兼容
└── *.test.ts                      # 测试
```

## 相关模块

- [src/agents/](../agents/CLAUDE.md) - AI 代理
- [src/memory/](../memory/CLAUDE.md) - 记忆管理

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
