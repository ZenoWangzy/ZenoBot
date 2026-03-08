# VPN 检测后自动恢复 Discord 连接 - 设计文档

> 日期：2026-02-16
> 状态：已批准

## 背景

用户使用饿饭加速器 (efan) 作为 VPN，VPN 连接后 Discord 经常需要手动重连。需要自动检测 VPN 状态变化并触发 Discord 重连。

## 需求

- **VPN 类型**：饿饭加速器，使用 `utun7` 接口
- **触发条件**：VPN 连接时 + VPN 断开后重连时
- **重连方式**：仅重启 Discord 渠道（不影响其他渠道）
- **检测频率**：60 秒

## 设计

### 架构

```
~/.openclaw/scripts/
├── vpn-watch.sh           # 主监控脚本（60秒轮询）
└── vpnwatch-manager.sh    # 管理工具

~/Library/LaunchAgents/
└── com.openclaw.vpn-watcher.plist  # LaunchAgent 配置

~/.openclaw/logs/
└── vpn-watch.log          # 日志文件
```

### VPN 检测逻辑

检测 `utun7` 接口状态：

```bash
check_vpn() {
    if ifconfig utun7 2>/dev/null | grep -q "inet "; then
        return 0  # VPN 已连接
    fi
    return 1  # VPN 未连接
}
```

状态变化检测：

| 状态变化          | 操作              |
| ----------------- | ----------------- |
| VPN_OFF → VPN_ON  | 触发 Discord 重连 |
| VPN_ON → VPN_OFF  | 仅记录日志        |
| VPN_ON → VPN_ON   | 无操作            |
| VPN_OFF → VPN_OFF | 无操作            |

防抖机制：VPN 状态需稳定 2 次检测（约 2 分钟）后才触发。

### Discord 重启机制

通过 launchctl 重启 Gateway（与现有 `network-watch.sh` 一致）：

```bash
restart_gateway() {
    launchctl unload "$GATEWAY_PLIST" 2>/dev/null
    sleep 2
    launchctl load "$GATEWAY_PLIST" 2>/dev/null
}
```

**说明**：Gateway 目前不支持单独重启某个渠道，因此采用重启整个 Gateway 的方式。重启后所有渠道（Discord、WhatsApp、Telegram 等）会自动重连。

错误处理：

- Gateway plist 不存在时：记录日志，跳过
- 重启失败时：记录失败原因，下次 VPN 变化时重试

### 管理工具

`vpnwatch-manager.sh` 命令：

```bash
install    # 安装并启动
uninstall  # 卸载
status     # 查看状态
logs       # 查看日志
```

### LaunchAgent 配置

- 登录后自动启动
- 崩溃后自动重启
- 每 60 秒检测一次 VPN 状态

### 日志格式

```
[2026-02-16 12:00:00] VPN watcher started
[2026-02-16 12:01:00] VPN connected (utun7)
[2026-02-16 12:01:00] Triggering Discord restart...
[2026-02-16 12:01:01] Discord channel restarted successfully
```

## 实现清单

1. 创建 `vpn-watch.sh` 主监控脚本
2. 创建 `vpnwatch-manager.sh` 管理工具
3. 创建 `com.openclaw.vpn-watcher.plist` LaunchAgent 配置
4. 测试并安装
