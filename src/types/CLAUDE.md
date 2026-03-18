[根目录](../../CLAUDE.md) > [src](../) > **types**

# Types

## 模块职责

Types 模块提供全局类型定义，包括：

1. **共享类型** - 跨模块使用的公共类型
2. **类型工具** - TypeScript 类型工具和守卫
3. **API 类型** - API 请求/响应的类型定义

## 入口与启动

- 主入口：`index.ts`

## 对外接口

### 核心类型

| 类型 | 描述 |
|------|------|
| `Message` | 消息结构 |
| `Channel` | 通道定义 |
| `Session` | 会话类型 |
| `Config` | 配置类型 |

## 使用方式

```typescript
import type { Message, Channel } from '../types';
```

## 相关文件清单

```
src/types/
├── index.ts           # 类型导出
├── message.ts         # 消息类型
├── channel.ts         # 通道类型
├── session.ts         # 会话类型
└── config.ts          # 配置类型
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
