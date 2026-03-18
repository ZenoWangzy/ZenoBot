[根目录](../../CLAUDE.md) > [src](../) > **scripts**

# Internal Scripts

## 模块职责

src/scripts 模块包含内部脚本工具，用于：

1. **构建辅助** - 构建过程中的辅助脚本
2. **CI 工具** - CI/CD 相关的工具脚本
3. **代码生成** - 自动生成代码的脚本

## 入口与启动

- 通过构建脚本或 CI 流程调用

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `canvas-a2ui-copy.ts` | A2UI 复制脚本 |
| `ci-changed-scope.ts` | CI 变更范围检测 |

## 关键依赖与配置

### 使用方式

```bash
# 通过 pnpm 脚本调用
node --import tsx scripts/canvas-a2ui-copy.ts
```

## 测试与质量

- 测试文件：`*.test.ts`

## 相关文件清单

```
src/scripts/
├── canvas-a2ui-copy.ts            # A2UI 复制
├── ci-changed-scope.ts            # CI 变更检测
└── *.test.ts                      # 测试
```

## 相关模块

- [scripts/](../../scripts/CLAUDE.md) - 主脚本目录

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
