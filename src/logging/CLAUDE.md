[根目录](../../CLAUDE.md) > [src](../) > **logging**

# Logging

## 模块职责

Logging 模块负责日志记录，包括：

1. **结构化日志** - 结构化的日志输出
2. **日志级别** - 支持 debug/info/warn/error 级别
3. **日志传输** - 支持多种日志输出目标
4. **日志轮转** - 日志文件的轮转和清理

## 入口与启动

- 主入口：`index.ts` 或 `logging.ts`
- 日志配置通过环境变量控制

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `logger.ts` | 日志器 |
| `logging.ts` | 日志配置 |
| `transport.ts` | 日志传输 |

### 使用方式

```typescript
import { logger } from '../logging';

logger.info('Operation completed');
logger.error({ err }, 'Operation failed');
```

## 关键依赖与配置

### 依赖

- `tslog` - 结构化日志库

### 配置

```json
{
  "logging": {
    "level": "info",
    "format": "json",
    "output": ["console", "file"]
  }
}
```

### 环境变量

```bash
DEBUG=openclaw:*    # 启用调试日志
LOG_LEVEL=debug     # 设置日志级别
```

## 测试与质量

- 测试文件：`logger.test.ts`

## 相关文件清单

```
src/logging/
├── index.ts           # 日志导出
├── logger.ts          # 日志器
├── logging.ts         # 日志配置
├── transport.ts       # 日志传输
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
