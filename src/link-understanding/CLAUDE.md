[根目录](../../CLAUDE.md) > [src](../) > **link-understanding**

# Link Understanding

## 模块职责

Link Understanding 模块负责 URL 和链接的智能处理，包括：

1. **链接检测** - 检测消息中的 URL
2. **内容提取** - 提取链接页面的内容
3. **格式化** - 格式化提取的内容
4. **运行器** - 链接处理的执行流程

## 入口与启动

- 主入口：`runner.ts`
- 检测：`detect.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `runner.ts` | 处理运行器 |
| `detect.ts` | 链接检测 |
| `apply.ts` | 内容应用 |
| `format.ts` | 格式化 |
| `defaults.ts` | 默认配置 |

## 关键依赖与配置

### 依赖

- `@mozilla/readability` - 页面内容提取
- `linkedom` - DOM 解析

### 配置

```json
{
  "linkUnderstanding": {
    "enabled": true,
    "maxContentLength": 10000,
    "timeout": 30000
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖检测、提取、格式化

## 相关文件清单

```
src/link-understanding/
├── runner.ts                      # 处理运行器
├── detect.ts                      # 链接检测
├── apply.ts                       # 内容应用
├── format.ts                      # 格式化
├── defaults.ts                    # 默认配置
└── *.test.ts                      # 测试
```

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
