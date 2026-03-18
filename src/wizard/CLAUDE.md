[根目录](../../CLAUDE.md) > [src](../) > **wizard**

# Wizard

## 模块职责

Wizard 模块提供交互式配置向导，包括：

1. **引导式设置** - 新用户的初始配置流程
2. **通道配置** - 通道的交互式配置
3. **问题诊断** - 通过问答诊断问题

## 入口与启动

- 主入口：`index.ts`
- CLI 命令：`openclaw wizard` 或 `openclaw onboarding`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 向导导出 |
| `onboarding.ts` | 新手引导 |
| `channel-setup.ts` | 通道设置 |

## 关键依赖与配置

### 依赖

- `@clack/prompts` - 交互式提示
- `osc-progress` - 进度显示

## 测试与质量

- 测试文件：`*.test.ts`
- E2E 测试：`*.e2e.test.ts`

## 相关文件清单

```
src/wizard/
├── index.ts           # 向导导出
├── onboarding.ts      # 新手引导
├── channel-setup.ts   # 通道设置
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
