[根目录](../../CLAUDE.md) > [src](../) > **hooks**

# Hooks

## 模块职责

Hooks 模块提供事件钩子系统，允许在特定事件发生时执行自定义逻辑：

1. **生命周期钩子** - 在消息发送前后、会话开始/结束等执行
2. **事件订阅** - 订阅和触发自定义事件
3. **中间件模式** - 支持中间件链式处理

## 入口与启动

- 主入口：`index.ts`
- 钩子配置在 `src/config/` 中管理

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 钩子导出 |
| `types.ts` | 钩子类型定义 |
| `registry.ts` | 钩子注册表 |

### 可用钩子

| 钩子 | 触发时机 |
|------|----------|
| `onMessageReceived` | 收到消息时 |
| `onMessageSent` | 发送消息后 |
| `onSessionStart` | 会话开始时 |
| `onSessionEnd` | 会话结束时 |
| `onToolCall` | 工具调用时 |

## 关键依赖与配置

### 配置

```json
{
  "hooks": {
    "enabled": true,
    "timeout": 5000
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖钩子注册、触发、错误处理

## 相关文件清单

```
src/hooks/
├── index.ts           # 钩子导出
├── types.ts           # 类型定义
├── registry.ts        # 注册表
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
