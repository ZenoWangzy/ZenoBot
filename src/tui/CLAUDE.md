[根目录](../../CLAUDE.md) > [src](../) > **tui**

# TUI (Terminal User Interface)

## 模块职责

TUI 模块提供终端用户界面，包括：

1. **交互式界面** - 终端内的交互式 UI
2. **菜单导航** - 键盘导航的菜单系统
3. **实时更新** - 界面的实时刷新和更新

## 入口与启动

- 主入口：`index.ts`
- CLI 命令：`openclaw tui`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | TUI 导出 |
| `app.ts` | 主应用 |
| `components/` | UI 组件 |

## 关键依赖与配置

### 依赖

- `@mariozechner/pi-tui` - TUI 框架
- `@clack/prompts` - 交互式提示

### 启动

```bash
pnpm tui
# 或
pnpm tui:dev  # 开发模式
```

## 测试与质量

- 测试文件：`*.test.ts`

## 相关文件清单

```
src/tui/
├── index.ts           # TUI 导出
├── app.ts             # 主应用
├── components/        # UI 组件
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
