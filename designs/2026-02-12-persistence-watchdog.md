# OpenClaw 持久化运行与 WhatsApp 自动重连方案

> **设计日期**: 2025-02-12
> **目标**: 确保 OpenClaw Gateway 在 Mac 唤醒后自动启动，WhatsApp 连接断开时自动重连，无需手动扫码登录

---

## 第一部分：整体架构

这是一个**两层防护**的持久化方案：

```
┌─────────────────────────────────────────────────────────┐
│                    macOS 主机                       │
│                                                     │
│  ┌───────────────────────────────────────────────┐   │
│  │   LaunchAgent (系统级守护)                  │   │
│  │   - 开机/唤醒自动启动                      │   │
│  │   - 崩溃后自动重启                        │   │
│  │   - 独立于用户登录状态                    │   │
│  └─────────────────┬─────────────────────────┘   │
│                    │ 启动                          │
│                    ▼                              │
│  ┌───────────────────────────────────────────────┐   │
│  │   OpenClaw Gateway                         │   │
│  │                                          │   │
│  │  ┌─────────────────────────────────────┐   │   │
│  │  │  WhatsApp Watchdog (新增)          │   │   │
│  │  │  - 心跳检测                        │   │   │
│  │  │  - 自动重连（指数退避）            │   │   │
│  │  │  - 失败计数 + 通知                │   │   │
│  │  └─────────────────────────────────────┘   │   │
│  │                                          │   │
│  │  ┌─────────────────────────────────────┐   │   │
│  │  │  WhatsApp Provider                │   │   │   │
│  │  │  - 复用现有凭证                  │   │   │   │
│  │  │  - 接收 watchdog 信号            │   │   │   │
│  │  └─────────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────┘   │
│                                                     │
│  ┌───────────────────────────────────────────────┐   │
│  │   通知渠道（可配置）                     │   │
│  │  - 桌面通知 (macOS notification)         │   │
│  │  - 日志文件                              │   │
│  │  - Web UI 提示                          │   │
│  └───────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**核心设计原则**：

1. **关注点分离** - 系统级启动 vs 应用级重连
2. **凭证复用** - WhatsApp 凭证已持久化在 `~/.openclaw/credentials/whatsapp/default/`，无需重复扫码
3. **优雅降级** - 多次重试失败后才通知用户

---

## 第二部分：实现方案

### 2.1 LaunchAgent 配置

创建 `~/Library/LaunchAgents/com.openclaw.gateway.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.gateway</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/pnpm</string>
        <string>openclaw</string>
        <string>gateway</string>
        <string>--port</string>
        <string>18789</string>
        <string>--verbose</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>

    <key>WorkingDirectory</key>
    <string>/Users/ZenoWang/Documents/project/openclaw</string>

    <key>StandardOutPath</key>
    <string>/tmp/openclaw-gateway.stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-gateway.stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**安装命令**：

```bash
# 复制 plist 文件
cp com.openclaw.gateway.plist ~/Library/LaunchAgents/

# 加载 LaunchAgent
launchctl load ~/Library/LaunchAgents/com.openclaw.gateway.plist

# 启动服务
launchctl start com.openclaw.gateway
```

### 2.2 WhatsApp Watchdog 实现

在 Gateway 中添加 Watchdog 模块，检测并重连断开的 WhatsApp 连接。

**检测策略**：

1. **心跳检测** - 定期检查 WhatsApp Provider 的连接状态
2. **消息超时** - 检测最近一次成功消息的时间戳
3. **WebSocket 状态** - 监听底层 WebSocket 的 close/error 事件

**重连策略（指数退避）**：

```typescript
const RETRY_DELAYS = [5s, 15s, 30s, 60s, 120s, 300s]; // 最大 5 分钟

async function reconnectWithBackoff(attempt: number) {
  const delay = RETRY_DELAYS[Math.min(attempt, RETRY_DELAYS.length - 1)];
  await sleep(delay);

  const success = await attemptReconnect();
  if (!success && attempt < MAX_RETRIES) {
    await reconnectWithBackoff(attempt + 1);
  }
}
```

**失败阈值**：

- 连续失败 3 次：记录警告日志
- 连续失败 5 次：发送桌面通知
- 连续失败 10 次：暂停重连，等待人工介入

### 2.3 通知机制

使用 macOS 原生通知 API (`terminal-notifier` 或 `osascript`)：

```typescript
function notifyUser(title: string, message: string) {
  exec(`osascript -e 'display notification "${message}" with title "${title}"'`);
}
```

**通知级别**：
| 级别 | 触发条件 | 通知方式 |
|------|----------|----------|
| INFO | 连接成功恢复 | 仅日志 |
| WARN | 重连失败 3 次 | 日志 + Web UI |
| ERROR | 需要人工介入 | 桌面通知 + 日志 |

---

## 第三部分：操作流程

### 3.1 正常流程

```
1. Mac 开机/唤醒 → LaunchAgent 自动启动 Gateway
2. Gateway 加载已保存的 WhatsApp 凭证
3. WhatsApp Provider 自动连接（无需扫码）
4. Watchdog 开始监控连接状态
5. 连接稳定 → 无需人工干预
```

### 3.2 断线重连流程

```
1. Watchdog 检测到连接断开
2. 记录日志："[whatsapp] 连接断开，开始重连"
3. 执行指数退避重连
4. 重连成功 → 通知："[whatsapp] 连接已恢复"
5. 重连失败 → 累加失败计数
6. 达到阈值 → 通知用户："WhatsApp 连接失败，请检查网络或手动重启"
```

### 3.3 人工介入流程

```
1. 用户收到失败通知
2. 检查网络连接
3. 如需重置：launchctl restart com.openclaw.gateway
4. 或通过 Web UI 手动重连
```

---

## 第四部分：配置文件

### 4.1 Watchdog 配置

在 `~/.openclaw/openclaw.json` 中添加：

```json
{
  "channels": {
    "whatsapp": {
      "watchdog": {
        "enabled": true,
        "heartbeatInterval": 30000, // 30 秒检测一次
        "messageTimeout": 120000, // 2 分钟无消息视为超时
        "maxRetries": 10,
        "retryDelays": [5000, 15000, 30000, 60000, 120000, 300000],
        "notifyThreshold": {
          "warn": 3,
          "error": 5,
          "manual": 10
        }
      }
    }
  }
}
```

---

## 第五部分：后续优化方向

1. **网络状态感知** - 检测 macOS 网络变化事件，智能决定重连时机
2. **远程监控** - 添加 Webhook 通知，支持推送到手机
3. **健康检查 API** - 提供统一的健康检查端点，便于集成监控工具

---

## 附录：相关文件位置

| 文件             | 路径                                                  |
| ---------------- | ----------------------------------------------------- |
| LaunchAgent 配置 | `~/Library/LaunchAgents/com.openclaw.gateway.plist`   |
| WhatsApp 凭证    | `~/.openclaw/credentials/whatsapp/default/creds.json` |
| Gateway 日志     | `/tmp/openclaw/openclaw-YYYY-MM-DD.log`               |
| 配置文件         | `~/.openclaw/openclaw.json`                           |
| 设计文档         | `/Users/ZenoWang/Documents/project/openclaw/designs/` |
