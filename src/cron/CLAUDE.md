[根目录](../../CLAUDE.md) > [src](../) > **cron**

# Cron

## 模块职责

Cron 模块提供定时任务功能，包括：

1. **定时任务调度** - 支持 cron 表达式的任务调度
2. **任务管理** - 创建、更新、删除定时任务
3. **任务持久化** - 任务配置的持久化存储
4. **错误处理** - 任务执行失败的处理和重试

## 入口与启动

- 主入口：`index.ts`
- 依赖 `croner` 库

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | Cron 导出 |
| `scheduler.ts` | 调度器 |
| `types.ts` | 类型定义 |

### 使用方式

```typescript
import { scheduleTask } from '../cron';

// 每天 9:00 执行
scheduleTask('0 9 * * *', async () => {
  console.log('Good morning!');
});
```

## 关键依赖与配置

### 依赖

- `croner` - Cron 表达式解析和调度

### 配置

```json
{
  "cron": {
    "enabled": true,
    "timezone": "UTC"
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖调度、取消、错误处理

## 相关文件清单

```
src/cron/
├── index.ts           # Cron 导出
├── scheduler.ts       # 调度器
├── types.ts           # 类型定义
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
