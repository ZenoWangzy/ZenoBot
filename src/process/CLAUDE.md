[根目录](../../CLAUDE.md) > [src](../) > **process**

# Process

## 模块职责

Process 模块负责进程管理和命令执行，包括：

1. **命令执行** - 执行系统命令和脚本
2. **进程管理** - 管理子进程的生命周期
3. **进程树** - 处理进程树和进程组
4. **命令队列** - 命令的队列化执行
5. **车道管理** - 并发执行的车道控制

## 入口与启动

- 主入口：`exec.ts`
- 进程桥接：`child-process-bridge.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `exec.ts` | 命令执行 |
| `child-process-bridge.ts` | 子进程桥接 |
| `kill-tree.ts` | 进程树终止 |
| `command-queue.ts` | 命令队列 |
| `lanes.ts` | 车道管理 |

## 关键依赖与配置

### 执行选项

```typescript
interface ExecOptions {
  timeout: number;
  cwd: string;
  env: Record<string, string>;
  shell: boolean;
}
```

### 进程管理

```typescript
// 终止进程树
await killTree(pid);

// 命令队列
const queue = new CommandQueue();
queue.enqueue(command);
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖执行、队列、终止

## 相关文件清单

```
src/process/
├── exec.ts                        # 命令执行
├── child-process-bridge.ts        # 子进程桥接
├── kill-tree.ts                   # 进程树终止
├── command-queue.ts               # 命令队列
├── lanes.ts                       # 车道管理
└── *.test.ts                      # 测试
```

## 相关模块

- [src/node-host/](../node-host/CLAUDE.md) - Node 宿主
- [src/daemon/](../daemon/CLAUDE.md) - 守护进程

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
