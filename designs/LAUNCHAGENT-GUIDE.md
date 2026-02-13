# OpenClaw Gateway LaunchAgent 使用指南

> 自动启动和持久化运行配置

## 📋 概述

通过 macOS LaunchAgent 实现 OpenClaw Gateway 的：

- ✅ 开机/登录自动启动
- ✅ 崩溃后自动重启
- ✅ WhatsApp 凭证复用（无需重复扫码）
- ✅ Mac 唤醒后自动恢复服务

## 🔧 安装状态

| 文件             | 状态      | 路径                                                |
| ---------------- | --------- | --------------------------------------------------- |
| LaunchAgent 配置 | ✅ 已安装 | `~/Library/LaunchAgents/com.openclaw.gateway.plist` |
| Gateway 进程     | ✅ 运行中 | PID: 83566                                          |
| WhatsApp 连接    | ✅ 已连接 | +8613162112932                                      |

## 🚀 管理命令

### 方式一：使用便捷脚本（推荐）

```bash
# 查看状态
./scripts/launchctl-status.sh

# 重启服务
./scripts/launchctl-restart.sh

# 停止服务
./scripts/launchctl-stop.sh
```

### 方式二：使用 launchctl 命令

```bash
# 查看状态
launchctl list | grep openclaw

# 重启服务
launchctl unload ~/Library/LaunchAgents/com.openclaw.gateway.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.gateway.plist

# 停止服务
launchctl unload ~/Library/LaunchAgents/com.openclaw.gateway.plist
```

## 📱 WhatsApp 连接

### 无需扫码原理

WhatsApp 凭证已持久化存储在：

```
~/.openclaw/credentials/whatsapp/default/creds.json
```

每次 Gateway 启动时会自动加载这些凭证，实现**无缝重连**。

### 检查连接状态

```bash
# 方法1：使用状态脚本
./scripts/launchctl-status.sh

# 方法2：查看日志
tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | grep WhatsApp

# 成功连接的标志：
# "WhatsApp Web connected."
# "Listening for personal WhatsApp inbound messages."
```

## 📝 日志位置

| 日志类型           | 路径                                    |
| ------------------ | --------------------------------------- |
| Gateway 主日志     | `/tmp/openclaw/openclaw-YYYY-MM-DD.log` |
| LaunchAgent stdout | `/tmp/openclaw-gateway.stdout.log`      |
| LaunchAgent stderr | `/tmp/openclaw-gateway.stderr.log`      |

## ⚠️ 故障排查

### Gateway 未自动启动

```bash
# 检查 LaunchAgent 是否加载
launchctl list | grep com.openclaw.gateway

# 如果没有，手动加载
launchctl load ~/Library/LaunchAgents/com.openclaw.gateway.plist

# 查看错误日志
cat /tmp/openclaw-gateway.stderr.log
```

### WhatsApp 连接失败

```bash
# 1. 检查网络连接
ping -c 3 web.whatsapp.com

# 2. 查看详细日志
tail -50 /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log

# 3. 如果提示需要重新扫码，说明凭证已过期
# 删除旧凭证后重启：
rm ~/.openclaw/credentials/whatsapp/default/creds.json
./scripts/launchctl-restart.sh
```

### 端口被占用

```bash
# 查看占用进程
lsof -i :18789

# 如果是其他进程，先杀掉
kill -9 <PID>
```

## 🔄 后续改进

查看完整设计方案：`designs/2026-02-12-persistence-watchdog.md`

待实现功能：

- [ ] WhatsApp Watchdog 自动重连模块
- [ ] 桌面通知集成
- [ ] 网络状态感知

## 📞 技术支持

如有问题，请检查：

1. [设计方案文档](./2026-02-12-persistence-watchdog.md)
2. Gateway 日志文件
3. LaunchAgent 错误日志
