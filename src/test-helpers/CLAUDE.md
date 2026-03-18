[根目录](../../CLAUDE.md) > [src](../) > **test-helpers**

# Test Helpers

## 模块职责

Test Helpers 模块提供测试辅助工具，包括：

1. **SSRF 防护** - 测试中的 SSRF 防护
2. **状态目录** - 测试用的状态目录管理
3. **工作空间** - 测试工作空间工具

## 入口与启动

- 在测试文件中按需导入

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `ssrf.ts` | SSRF 防护工具 |
| `state-dir-env.ts` | 状态目录环境 |
| `workspace.ts` | 工作空间工具 |

## 关键依赖与配置

### 使用方式

```typescript
import { setupTestStateDir } from '../test-helpers/state-dir-env';
import { createTestWorkspace } from '../test-helpers/workspace';
```

### 状态目录

测试时使用临时目录：

```typescript
const stateDir = await setupTestStateDir();
// 测试结束后自动清理
```

## 测试与质量

- 测试文件：`*.test.ts`

## 相关文件清单

```
src/test-helpers/
├── ssrf.ts                        # SSRF 防护
├── state-dir-env.ts               # 状态目录
├── workspace.ts                   # 工作空间
└── *.test.ts                      # 测试
```

## 相关模块

- [src/test-utils/](../test-utils/CLAUDE.md) - 测试工具

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
