[根目录](../../CLAUDE.md) > [src](../) > **terminal**

# Terminal

## 模块职责

Terminal 模块负责终端 UI 相关功能，包括：

1. **终端输出** - 格式化终端输出
2. **颜色方案** - 统一的颜色调色板
3. **表格渲染** - 终端表格显示
4. **进度显示** - 进度条和加载状态

## 入口与启动

- 主入口：`index.ts`
- 调色板：`palette.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 终端导出 |
| `palette.ts` | 颜色调色板（Lobster seam） |
| `table.ts` | 表格渲染 |
| `progress.ts` | 进度显示 |

## 关键依赖与配置

### 调色板使用

使用共享的 CLI 调色板，不要硬编码颜色：

```typescript
import { palette } from '../terminal/palette';

console.log(palette.highlight('重要信息'));
console.log(palette.muted('次要信息'));
```

### 依赖

- `osc-progress` - 进度显示
- `@clack/prompts` - 交互式提示

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖表格、进度、颜色

## 相关文件清单

```
src/terminal/
├── index.ts           # 终端导出
├── palette.ts         # 颜色调色板
├── table.ts           # 表格渲染
├── progress.ts        # 进度显示
├── format.ts          # 格式化工具
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
