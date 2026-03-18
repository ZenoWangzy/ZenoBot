[根目录](../../CLAUDE.md) > [src](../) > **test-utils**

# Test Utils

## 模块职责

Test Utils 模块提供测试工具和断言，包括：

1. **断言工具** - 专用的测试断言
2. **测试固件** - 测试用的固件数据
3. **命令运行器** - 测试中的命令执行
4. **通道测试** - 通道插件的测试工具
5. **环境工具** - 测试环境配置

## 入口与启动

- 在测试文件中按需导入

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `env.ts` | 环境配置 |
| `command-runner.ts` | 命令运行器 |
| `exec-assertions.ts` | 执行断言 |
| `auth-token-assertions.ts` | 认证断言 |

### 通道测试

| 模块 | 职责 |
|------|------|
| `channel-plugins.ts` | 通道插件测试 |
| `channel-plugin-test-fixtures.ts` | 测试固件 |

### 其他工具

| 模块 | 职责 |
|------|------|
| `chunk-test-helpers.ts` | 分块测试 |
| `camera-url-test-helpers.ts` | 相机 URL 测试 |

## 关键依赖与配置

### 使用方式

```typescript
import { runCommand } from '../test-utils/command-runner';
import { assertAuthToken } from '../test-utils/auth-token-assertions';
import { setupTestEnv } from '../test-utils/env';
```

### 环境变量

```typescript
// 设置测试环境
setupTestEnv({
  OPENCLAW_TEST: '1',
  NODE_ENV: 'test'
});
```

## 测试与质量

- 测试文件：`*.test.ts`

## 相关文件清单

```
src/test-utils/
├── env.ts                         # 环境配置
├── command-runner.ts              # 命令运行器
├── exec-assertions.ts             # 执行断言
├── auth-token-assertions.ts       # 认证断言
├── channel-plugins.ts             # 通道插件测试
├── channel-plugin-test-fixtures.ts # 测试固件
├── chunk-test-helpers.ts          # 分块测试
├── camera-url-test-helpers.ts     # 相机 URL 测试
└── *.test.ts                      # 测试
```

## 相关模块

- [src/test-helpers/](../test-helpers/CLAUDE.md) - 测试辅助

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
