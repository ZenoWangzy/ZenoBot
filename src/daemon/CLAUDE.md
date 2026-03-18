[根目录](../../CLAUDE.md) > [src](../) > **daemon**

# Daemon

## 模块职责

Daemon 模块负责后台守护进程管理，包括：

1. **进程管理** - 启动、停止、重启后台进程
2. **launchd 集成** - macOS launchd 服务管理
3. **进程监控** - 监控进程健康状态
4. **日志管理** - 守护进程的日志输出

## 入口与启动

- 主入口：`index.ts`
- macOS：通过 launchd 管理

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | Daemon 导出 |
| `launchd.ts` | launchd 集成 |
| `process.ts` | 进程管理 |

## 关键依赖与配置

### macOS launchd

- 当前 Gateway 仅作为菜单栏应用运行
- 没有单独的 LaunchAgent/helper 标签安装
- 重启通过 OpenClaw Mac 应用或 `scripts/restart-mac.sh`

### 验证命令

```bash
launchctl print gui/$UID | grep openclaw
```

## 测试与质量

- 测试文件：`*.test.ts`
- 集成测试：`*.integration.test.ts`

## 相关文件清单

```
src/daemon/
├── index.ts              # Daemon 导出
├── launchd.ts            # launchd 集成
├── process.ts            # 进程管理
├── *.integration.test.ts # 集成测试
└── *.test.ts             # 单元测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
