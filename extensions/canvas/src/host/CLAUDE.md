[根目录](../../CLAUDE.md) > [src](../) > **canvas-host**

# Canvas Host

## 模块职责

Canvas Host 模块负责画布功能的服务端托管，包括：

1. **A2UI 集成** - Angular 2 UI 框架集成
2. **文件解析** - 画布文件解析和处理
3. **服务器** - 画布内容的服务端托管

## 入口与启动

- 主入口：`server.ts`
- A2UI 集成：`a2ui.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `server.ts` | 画布服务器 |
| `a2ui.ts` | A2UI 集成 |
| `file-resolver.ts` | 文件解析 |

### A2UI 目录

- `a2ui/` - A2UI 资源和配置
- `.bundle.hash` - 打包哈希（自动生成）

## 关键依赖与配置

### 构建命令

```bash
pnpm canvas:a2ui:bundle  # 打包 A2UI
```

### 注意事项

- `.bundle.hash` 是自动生成的，不要手动编辑
- 只有在需要时才重新打包 A2UI

## 测试与质量

- 测试文件：`*.test.ts`

## 相关文件清单

```
src/canvas-host/
├── server.ts                      # 画布服务器
├── a2ui.ts                        # A2UI 集成
├── file-resolver.ts               # 文件解析
├── a2ui/                          # A2UI 资源
│   └── .bundle.hash               # 打包哈希
└── *.test.ts                      # 测试
```

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
