[根目录](../CLAUDE.md) > **scripts**

---

# Scripts 模块

> 构建部署脚本

---

## 变更记录 (Changelog)

### 2026-03-11
- 添加 Windows PowerShell 监控脚本
- openclaw-health-check.ps1
- openclaw-fix.ps1
- discord-response-check.ps1
- openclaw-monitor.ps1

### 2026-03-06
- 添加 clawlog.sh 文档、运维类别

### 2026-02-11
- 创建模块文档

---

## 模块职责

`scripts/` 包含项目构建、部署和开发脚本。

### 主要脚本类别

| 类别 | 描述 |
|------|------|
| 构建 | TypeScript 构建、UI 打包 |
| 部署 | macOS/iOS/Android 打包 |
| 测试 | E2E 测试、Docker 测试 |
| 开发 | 开发服务器、文件监听 |
| 工具 | 代码生成、协议生成 |
| 运维 | Gateway 健康检查、自动修复、日志查询 |

---

## 关键脚本

| 脚本 | 描述 |
|------|------|
| `scripts/clawlog.sh` | macOS 统一日志查询（需要密码less sudo） |
| `scripts/run-node.mjs` | 运行 Node 入口 |
| `scripts/watch-node.mjs` | 文件监听模式 |
| `scripts/ui.js` | UI 构建/开发 |
| `scripts/protocol-gen.ts` | 协议生成 |
| `scripts/package-mac-app.sh` | macOS 打包 |
| `scripts/openclaw-health-check.sh` | Gateway 健康检查 (每30s) |
| `scripts/openclaw-fix.sh` | Gateway 自动修复 (Claude Code) |
| `scripts/install-monitor.sh` | 监控服务安装/卸载 |
| `scripts/openclaw-health-check.ps1` | Windows 健康检查 |
| `scripts/openclaw-fix.ps1` | Windows 自动修复 |
| `scripts/discord-response-check.ps1` | Windows Discord 响应检查 |
| `scripts/openclaw-monitor.ps1` | Windows 监控管理 |

---

## 日志查询

### clawlog.sh 用法
```bash
# 实时查看日志
./scripts/clawlog.sh -f

# 查看最近 120 行
./scripts/clawlog.sh -n 120

# 按类别过滤
./scripts/clawlog.sh -c gateway

# 仅显示错误
./scripts/clawlog.sh -e
```

---

## Windows 监控系统

### 脚本列表

| 脚本 | 功能 |
|------|------|
| `openclaw-health-check.ps1` | 健康检查 (进程 + HTTP 端点) |
| `openclaw-fix.ps1` | 自动修复 (Claude Code 诊断) |
| `discord-response-check.ps1` | Discord 响应检查 |
| `openclaw-monitor.ps1` | 任务计划程序管理 |

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway 端口 |
| `OPENCLAW_FIX_SCRIPT` | `scripts/openclaw-fix.ps1` | 修复脚本路径 |
| `OPENCLAW_DISCORD_CHECK_SCRIPT` | `scripts/discord-response-check.ps1` | Discord 检查脚本 |
| `OPENCLAW_HEALTH_CHECK_LOG` | `%TEMP%\openclaw-health-check.log` | 健康检查日志 |
| `OPENCLAW_FIX_LOG` | `%TEMP%\openclaw-fix.log` | 修复日志 |
| `OPENCLAW_MONITOR_LOG` | `%TEMP%\openclaw-monitor.log` | 监控日志 |
| `OPENCLAW_FIX_MAX_RETRIES` | `2` | 最大重试次数 |
| `OPENCLAW_CLAUDE_TIMEOUT` | `300` | Claude 超时(秒) |

### 使用示例

```powershell
# 安装监控任务 (每 1 分钟检查)
.\scripts\openclaw-monitor.ps1 install

# 自定义检查间隔 (每 5 分钟)
.\scripts\openclaw-monitor.ps1 install -IntervalMinutes 5

# 查看状态
.\scripts\openclaw-monitor.ps1 status

# 手动运行健康检查
.\scripts\openclaw-monitor.ps1 run

# 重启 Gateway
.\scripts\openclaw-monitor.ps1 restart

# 停止 Gateway
.\scripts\openclaw-monitor.ps1 stop

# 卸载监控
.\scripts\openclaw-monitor.ps1 uninstall
```

### 日志位置

所有日志文件位于 `%TEMP%` 目录:
- `openclaw-health-check.log` - 健康检查日志
- `openclaw-fix.log` - 自动修复日志
- `openclaw-monitor.log` - 监控管理日志
- `discord-response-check.log` - Discord 检查日志

### 故障排查

```powershell
# 查看 Gateway 进程
Get-Process -Name "node" | Where-Object { $_.CommandLine -like "*openclaw*" }

# 检查端口监听
Get-NetTCPConnection -LocalPort 18789 -State Listen

# 测试健康端点
Invoke-WebRequest -Uri "http://127.0.0.1:18789/health" -UseBasicParsing

# 查看任务状态
Get-ScheduledTask -TaskName 'OpenClaw-HealthCheck'
Get-ScheduledTaskInfo -TaskName 'OpenClaw-HealthCheck'

# 手动运行任务
Start-ScheduledTask -TaskName 'OpenClaw-HealthCheck'

# 查看日志
Get-Content $env:TEMP\openclaw-health-check.log -Tail 50
Get-Content $env:TEMP\openclaw-fix.log -Wait  # 实时监控
```

---

## 相关文件清单

```
scripts/
├── clawlog.sh              # macOS 日志查询
├── run-node.mjs            # 运行入口
├── watch-node.mjs          # 文件监听
├── ui.js                   # UI 脚本
├── protocol-gen.ts         # 协议生成
├── package-mac-app.sh      # macOS 打包
├── build-icon.sh           # 图标构建
├── openclaw-health-check.sh # Unix 健康检查
├── openclaw-fix.sh         # Unix 自动修复
├── discord-response-check.sh # Unix Discord 检查
├── install-monitor.sh      # 监控安装 (Unix)
├── openclaw-health-check.ps1 # Windows 健康检查
├── openclaw-fix.ps1        # Windows 自动修复
├── discord-response-check.ps1 # Windows Discord 检查
├── openclaw-monitor.ps1    # Windows 监控管理
├── docs-i18n/              # 文档国际化
│   └── *.go
├── docker/                 # Docker 脚本
├── e2e/                    # E2E 测试脚本
├── launchd/                # LaunchAgent 模板
│   └── ai.openclaw.monitor.plist
└── systemd/                # systemd 服务文件
```
