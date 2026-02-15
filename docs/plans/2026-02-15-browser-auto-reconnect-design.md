# 浏览器自动化连接稳定性设计

> 日期：2026-02-15
> 状态：已批准
> 作者：Claude + ZenoW

## 问题背景

当前 Gateway 通过 Chrome 扩展控制浏览器时存在严重的稳定性问题：

1. **初始连接** - 每次重启 Gateway 后需要手动点击扩展
2. **页面操作** - 滚动/点击/跳转都会导致连接断开
3. **执行中断** - Agent 正在操作时突然断开
4. **空闲超时** - 几秒不操作就断开

**用户期望**：出门时通过 Discord 发指令，Agent 完全自主操作浏览器，断开后自动恢复，零手动干预。

## 设计目标

- 全自动启动：Gateway 启动时自动检测/启动 Chrome 并连接
- 守护进程：持续监控连接状态，断开自动重连
- 状态恢复：重连后恢复之前的页面状态
- 保持登录：使用独立 Chrome profile，登录态持久化

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    Gateway 启动流程                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. 检测 Chrome 是否已以调试模式运行                              │
│     - 检查 127.0.0.1:9222 是否可连接                             │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│ 已运行调试模式 Chrome     │     │ 未运行或普通模式 Chrome           │
│ → 直连 CDP（首选）        │     │ → 尝试自动启动调试模式 Chrome      │
└─────────────────────────┘     │ → 失败则降级到扩展中继模式        │
                                └─────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. 守护进程（Connection Watchdog）                              │
│     - 每 5 秒检测连接状态                                         │
│     - 断开时自动重连                                              │
│     - 连续失败 3 次则重启浏览器                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 连接模式

| 模式 | 说明 | 优先级 |
|------|------|--------|
| CDP 直连 | 通过 --remote-debugging-port 直连 Chrome | 首选 |
| 扩展中继 | 通过 Chrome Extension Relay 中转 | 降级备选 |

## 详细设计

### 1. Chrome 启动器 (BrowserLauncher)

```typescript
// src/browser/launcher.ts
class BrowserLauncher {
  // 检测 Chrome 是否已在调试模式运行
  async detectExistingCDP(port = 9222): Promise<CDPInfo | null>

  // 以调试模式启动 Chrome
  async launchWithCDP(options: {
    port: number;          // 默认 9222
    profileDir: string;    // 独立 profile 目录
    startingUrl?: string;  // 启动时打开的 URL
    headless?: boolean;    // 是否无头模式
  }): Promise<ChromeProcess>

  // 查找 Chrome 可执行文件
  private findChromeExecutable(): string
}
```

**启动命令：**
```bash
chrome.exe \
  --remote-debugging-port=9222 \
  --user-data-dir="~/.openclaw/browser-profiles/default" \
  --no-first-run \
  --no-default-browser-check
```

### 2. 连接守护进程 (ConnectionWatchdog)

```typescript
// src/browser/watchdog.ts
class ConnectionWatchdog {
  private checkInterval = 5000;  // 5 秒检测一次
  private maxRetries = 3;        // 最大重试次数
  private consecutiveFailures = 0;

  start(): void
  stop(): void

  // 检测连接状态
  private async checkConnection(): Promise<boolean>

  // 重连逻辑
  private async reconnect(): Promise<boolean>

  // 重启浏览器
  private async restartBrowser(): Promise<void>

  // 监听 Browser.disconnected 事件
  private onBrowserDisconnected(): void
}
```

### 3. 状态恢复 (SessionStateRecovery)

```typescript
// src/browser/recovery.ts
interface SessionSnapshot {
  activeTabUrl: string;
  activeTabTitle: string;
  scrollPosition: { x: number; y: number };
  formData: Record<string, string>;
  timestamp: number;
}

class SessionStateRecovery {
  // 保存当前状态快照
  async saveSnapshot(): Promise<SessionSnapshot>

  // 恢复状态
  async restore(snapshot: SessionSnapshot): Promise<void>
}
```

### 4. 双模式连接 (PlaywrightSession 改造)

优先 CDP 直连，失败则降级到扩展中继模式。

### 5. 超时参数优化

| 参数 | 当前值 | 新值 | 说明 |
|------|--------|------|------|
| 心跳间隔 | 15s | 5s | 更频繁检测 |
| 连接超时 | 20s | 60s | 更宽容的等待 |
| 空闲超时 | 无 | 300s | 5 分钟无操作才断开 |
| 守护检测间隔 | 无 | 5s | 新增 |

### 6. 配置项

```yaml
# ~/.openclaw/config.yaml
browser:
  mode: auto  # auto | cdp-direct | extension-relay
  cdp:
    port: 9222
    autoLaunch: true
    profileDir: ~/.openclaw/browser-profiles/default
  watchdog:
    enabled: true
    checkInterval: 5000
    maxRetries: 3
    autoRestart: true
  timeouts:
    connect: 60000
    operation: 30000
    idle: 300000
```

## 使用流程

### 首次设置（一次性）

1. Gateway 启动 → 自动创建 profile 目录
2. 自动启动 Chrome（调试模式）
3. 用户在新 Chrome 中登录小红书等网站
4. 登录状态保存在 profile 中，之后永久有效

### 日常使用（零干预）

用户通过 Discord 发指令 → Gateway 检查连接 → 
已连接则执行 / 未连接则守护进程自动恢复后执行

## 文件改动清单

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| src/browser/launcher.ts | 新增 | Chrome 自动启动器 |
| src/browser/watchdog.ts | 新增 | 连接守护进程 |
| src/browser/recovery.ts | 新增 | 状态恢复机制 |
| src/browser/pw-session.ts | 修改 | 支持双模式连接 |
| src/browser/extension-relay.ts | 修改 | 优化心跳/超时参数 |
| src/browser/server-context.ts | 修改 | 集成新的启动/守护逻辑 |
| src/config/config.ts | 修改 | 新增 browser 配置项 |

## 风险与应对

| 风险 | 应对措施 |
|------|----------|
| 网站检测自动化 | 使用真实 Chrome profile + CDP 直连 |
| Chrome 更新后路径变化 | 多路径检测 + 配置可覆盖 |
| 登录态过期 | Agent 检测到未登录时通知用户 |
