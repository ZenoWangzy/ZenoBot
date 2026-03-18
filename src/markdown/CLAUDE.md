[根目录](../../CLAUDE.md) > [src](../) > **markdown**

# Markdown

## 模块职责

Markdown 模块负责 Markdown 处理，包括：

1. **Markdown 解析** - 解析 Markdown 文本
2. **Markdown 渲染** - 渲染为 HTML 或其他格式
3. **Markdown 清理** - 清理和规范化 Markdown
4. **语法高亮** - 代码块的语法高亮

## 入口与启动

- 主入口：`index.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | Markdown 导出 |
| `parser.ts` | 解析器 |
| `renderer.ts` | 渲染器 |
| `sanitize.ts` | 清理 |

## 关键依赖与配置

### 依赖

- `markdown-it` - Markdown 解析器
- `cli-highlight` - 代码高亮

### 使用方式

```typescript
import { renderMarkdown } from '../markdown';

const html = renderMarkdown('# Hello\n\nWorld');
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖解析、渲染、清理

## 相关文件清单

```
src/markdown/
├── index.ts           # Markdown 导出
├── parser.ts          # 解析器
├── renderer.ts        # 渲染器
├── sanitize.ts        # 清理
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
