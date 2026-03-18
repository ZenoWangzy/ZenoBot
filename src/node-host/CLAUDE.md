[根目录](../../CLAUDE.md) > [src](../) > **node-host**

# Node Host

## 模块职责

Node Host 模块负责 Node.js 环境下的命令执行和进程管理，包括：

1. **命令调用** - 在 Node 环境中执行系统命令
2. **执行策略** - 控制命令执行的权限和安全
3. **环境隔离** - 沙箱化的命令执行环境
4. **浏览器集成** - 浏览器环境下的命令执行

## 入口与启动

- 主入口：`invoke.ts`
- 执行策略：`exec-policy.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `invoke.ts` | 命令调用 |
| `invoke-browser.ts` | 浏览器环境调用 |
| `invoke-system-run.ts` | 系统命令执行 |
| `invoke-system-run-allowlist.ts` | 命令白名单 |
| `exec-policy.ts` | 执行策略 |

### 配置

| 模块 | 职责 |
|------|------|
| `config.ts` | Node Host 配置 |

## 关键依赖与配置

### 执行策略

```typescript
interface ExecPolicy {
  allowed: boolean;
  requiresApproval: boolean;
  timeout: number;
  env: Record<string, string>;
}
```

### 安全措施

- 命令白名单限制
- 环境变量清理
- 执行超时
- 权限审批流程

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖调用、策略、安全

## 相关文件清单

```
src/node-host/
├── invoke.ts                      # 命令调用
├── invoke-browser.ts              # 浏览器调用
├── invoke-system-run.ts           # 系统执行
├── invoke-system-run-allowlist.ts # 白名单
├── exec-policy.ts                 # 执行策略
├── config.ts                      # 配置
└── *.test.ts                      # 测试
```

## 相关模块

- [src/process/](../process/CLAUDE.md) - 进程管理

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
