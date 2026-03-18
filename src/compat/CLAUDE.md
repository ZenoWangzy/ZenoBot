[根目录](../../CLAUDE.md) > [src](../) > **compat**

# Compat (Compatibility)

## 模块职责

Compat 模块负责向后兼容性支持，包括：

1. **名称迁移** - 旧名称到新名称的映射
2. **配置迁移** - 旧配置格式的转换
3. **API 兼容** - 废弃 API 的兼容层

## 入口与启动

- 主入口：`index.ts` 或通过其他模块导入

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `legacy-names.ts` | 旧名称映射 |

## 使用方式

```typescript
import { resolveLegacyName } from '../compat';

const newName = resolveLegacyName('oldName');
```

## 关键依赖与配置

### 迁移策略

- 旧名称在读取时自动转换
- 写入时使用新名称
- 提供警告日志提示迁移

## 测试与质量

- 测试文件：`*.test.ts`

## 相关文件清单

```
src/compat/
├── legacy-names.ts                # 旧名称映射
└── *.test.ts                      # 测试
```

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
