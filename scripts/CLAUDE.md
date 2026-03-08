[根目录](../CLAUDE.md) > **scripts**

---

# Scripts 模块

> 构建部署脚本

---

## 变更记录 (Changelog)

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
├── openclaw-health-check.sh # 健康检查
├── openclaw-fix.sh         # 自动修复
├── install-monitor.sh      # 监控安装
├── docs-i18n/              # 文档国际化
│   └── *.go
├── docker/                 # Docker 脚本
├── e2e/                    # E2E 测试脚本
├── launchd/                # LaunchAgent 模板
│   └── ai.openclaw.monitor.plist
└── systemd/                # systemd 服务文件
```
