[根目录](../../CLAUDE.md) > [src](../) > **utils**

# Utils

## 模块职责

Utils 模块提供通用的工具函数，包括：

1. **字符串处理** - 字符串操作和格式化
2. **对象操作** - 深拷贝、合并等
3. **异步工具** - 超时、重试、并发控制
4. **类型工具** - 类型守卫和断言

## 入口与启动

- 主入口：`index.ts` 或 `utils.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `utils.ts` | 通用工具函数 |
| `async.ts` | 异步工具 |
| `string.ts` | 字符串处理 |
| `object.ts` | 对象操作 |

## 常用函数

### 异步工具

```typescript
// 带超时的 Promise
await withTimeout(promise, 5000);

// 重试
await retry(fn, { maxRetries: 3, delay: 1000 });

// 并发控制
await pMap(items, fn, { concurrency: 5 });
```

### 字符串工具

```typescript
// 截断
truncate('long text', 10); // 'long te...'

// 驼峰转换
camelCase('hello-world'); // 'helloWorld'
```

## 测试与质量

- 测试文件：`utils.test.ts`
- 覆盖所有工具函数

## 相关文件清单

```
src/utils/
├── utils.ts           # 通用工具
├── async.ts           # 异步工具
├── string.ts          # 字符串处理
├── object.ts          # 对象操作
├── types.ts           # 类型工具
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
