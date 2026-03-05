# 自愈网关系统设计文档 (Self-Healing Gateway Design)

> **日期**: 2026-03-05
> **状态**: 待实施
> **目标平台**: macOS (LaunchAgent)

---

## 1. 概述

### 1.1 目标

为 OpenClaw Gateway 实现自愈能力，当 Gateway 因异常退出时：

1. 自动检测故障
2. 使用 Claude Code CLI 进行智能诊断和修复
3. 重启 Gateway 服务
4. 通过 Wake Hook 通知 Gateway Agent → Discord

### 1.2 范围

- **包含**: macOS LaunchAgent 监控、Claude Code 自动修复、Wake Hook 通知
- **不包含**: codex-deep-search 技能（用户明确不需要）

---

## 2. 架构设计

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS 系统                               │
│                                                                  │
│  ┌──────────────────┐        ┌──────────────────────────────┐  │
│  │  ai.openclaw.     │        │   ai.openclaw.               │  │
│  │  gateway.plist    │        │   monitor.plist              │  │
│  │                   │        │                              │  │
│  │  ┌─────────────┐  │        │  ┌────────────────────────┐ │  │
│  │  │  Gateway    │  │        │  │  Health Monitor        │ │  │
│  │  │  Process    │◄─┼────────┼──┤  (每30s检查一次)        │ │  │
│  │  └─────────────┘  │        │  └────────────────────────┘ │  │
│  │         │         │        │            │                 │  │
│  │         ▼         │        │            ▼                 │  │
│  │  ┌─────────────┐  │        │  ┌────────────────────────┐ │  │
│  │  │   端口      │  │        │  │ openclaw-fix.sh        │ │  │
│  │  │   18789     │  │        │  │ (flock 锁, Claude修复)  │ │  │
│  │  └─────────────┘  │        │  └────────────────────────┘ │  │
│  └──────────────────┘        │            │                 │  │
│                               │            ▼                 │  │
│                               │  ┌────────────────────────┐ │  │
│                               │  │ POST /hooks/wake       │ │  │
│                               │  │ → Gateway Agent        │ │  │
│                               │  │ → Discord 消息          │ │  │
│                               │  └────────────────────────┘ │  │
│                               └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 核心组件

| 组件             | 文件路径                                           | 职责                        |
| ---------------- | -------------------------------------------------- | --------------------------- |
| 健康检查脚本     | `scripts/openclaw-health-check.sh`                 | 每30s检查 Gateway 健康状态  |
| 自动修复脚本     | `scripts/openclaw-fix.sh`                          | Claude Code 诊断修复 + 通知 |
| 监控 LaunchAgent | `~/Library/LaunchAgents/ai.openclaw.monitor.plist` | 定时运行健康检查            |

---

## 3. 数据流

### 3.1 正常流程（健康）

```
Health Monitor (每30s)
    │
    ▼
curl -s http://127.0.0.1:18789/health
    │
    ▼
返回 200 OK → 等待下一周期
```

### 3.2 故障修复流程

```
Health Monitor (每30s)
    │
    ▼
curl -s http://127.0.0.1:18789/health
    │
    ▼
连接失败/超时 → 调用 openclaw-fix.sh
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  openclaw-fix.sh                                            │
│                                                             │
│  1. flock /tmp/openclaw-fix.lock (防并发)                   │
│  2. 收集错误日志                                             │
│     - ~/.openclaw/logs/gateway.err.log                     │
│     - launchctl list | grep openclaw                       │
│     - lsof -i :18789                                       │
│  3. 构建修复提示词                                           │
│  4. 调用 Claude Code CLI                                    │
│     claude -p "$FIX_PROMPT" \                              │
│       --allowedTools Read,Write,Edit                       │
│  5. 重启 Gateway                                            │
│     launchctl kickstart -k gui/$UID/ai.openclaw.gateway    │
│  6. 验证健康状态 (最多重试2次)                               │
│  7. 通知结果                                                 │
│     curl -X POST http://127.0.0.1:18789/hooks/wake         │
│     → Gateway Agent → Discord                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 通知机制

```
修复完成
    │
    ▼
POST http://127.0.0.1:18789/hooks/wake
Content-Type: application/json

{
  "event": "gateway_auto_fix",
  "status": "success|failed",
  "timestamp": "2026-03-05T10:30:00Z",
  "retry_count": 1,
  "error_summary": "配置文件格式错误",
  "fix_action": "已修复 config.json 语法"
}
    │
    ▼
Gateway Agent 接收 → 发送 Discord 消息
```

---

## 4. 配置规范

### 4.1 环境变量

```bash
# ~/.config/openclaw/monitor.env (可选)
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_HEALTH_INTERVAL=30        # 健康检查间隔(秒)
OPENCLAW_FIX_MAX_RETRIES=2         # 最大修复重试次数
OPENCLAW_CLAUDE_TIMEOUT=300        # Claude Code 超时(秒)
```

### 4.2 LaunchAgent 配置

**监控服务** (`ai.openclaw.monitor.plist`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/ZenoWang/Documents/project/openclaw/scripts/openclaw-health-check.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/openclaw-monitor.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-monitor.err.log</string>
</dict>
</plist>
```

---

## 5. 脚本设计

### 5.1 健康检查脚本 (`openclaw-health-check.sh`)

```bash
#!/bin/bash
# OpenClaw Gateway 健康检查脚本

set -euo pipefail

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
FIX_SCRIPT="$(dirname "$0")/openclaw-fix.sh"
HEALTH_URL="http://127.0.0.1:${GATEWAY_PORT}/health"
TIMEOUT=5

# 检查健康状态
if ! curl -sf --max-time "$TIMEOUT" "$HEALTH_URL" > /dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Gateway unhealthy, triggering fix..."
    "$FIX_SCRIPT"
fi
```

### 5.2 自动修复脚本 (`openclaw-fix.sh`)

```bash
#!/bin/bash
# OpenClaw Gateway 自动修复脚本

set -euo pipefail

# 配置
LOCK_FILE="/tmp/openclaw-fix.lock"
MAX_RETRIES="${OPENCLAW_FIX_MAX_RETRIES:-2}"
CLAUDE_TIMEOUT="${OPENCLAW_CLAUDE_TIMEOUT:-300}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_LABEL="ai.openclaw.gateway"
LOG_FILE="/tmp/openclaw-fix.log"
GATEWAY_ERR_LOG="$HOME/.openclaw/logs/gateway.err.log"

# flock 锁，防止并发执行
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another fix is running, skipping..."
    exit 0
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

collect_errors() {
    local errors=""

    # 收集 Gateway 错误日志 (最后50行)
    if [[ -f "$GATEWAY_ERR_LOG" ]]; then
        errors+="\n=== Gateway Error Log ===\n"
        errors+="$(tail -50 "$GATEWAY_ERR_LOG" 2>/dev/null || echo "无法读取日志")"
    fi

    # 检查 LaunchAgent 状态
    errors+="\n=== LaunchAgent Status ===\n"
    errors+="$(launchctl list | grep openclaw || echo "未找到相关服务")"

    # 检查端口占用
    errors+="\n=== Port ${GATEWAY_PORT} Status ===\n"
    errors+="$(lsof -i :${GATEWAY_PORT} 2>/dev/null || echo "端口未监听")"

    echo -e "$errors"
}

restart_gateway() {
    log "Restarting Gateway..."
    launchctl kickstart -k gui/$UID/$GATEWAY_LABEL 2>/dev/null || true
    sleep 3
}

check_health() {
    curl -sf --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/health" > /dev/null 2>&1
}

notify_result() {
    local status="$1"
    local retry_count="$2"
    local error_summary="$3"
    local fix_action="$4"

    # 等待 Gateway 恢复后再通知
    sleep 2

    local payload=$(cat <<EOF
{
  "event": "gateway_auto_fix",
  "status": "${status}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "retry_count": ${retry_count},
  "error_summary": "$(echo "$error_summary" | head -c 200 | tr '"' "'")",
  "fix_action": "${fix_action}"
}
EOF
)

    curl -sf -X POST "http://127.0.0.1:${GATEWAY_PORT}/hooks/wake" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || log "Warning: Failed to send notification"
}

# 主流程
main() {
    log "=== Starting auto-fix process ==="

    local errors
    errors=$(collect_errors)

    # 构建修复提示词
    local fix_prompt="OpenClaw Gateway 异常退出，请诊断并修复问题。

错误信息:
$errors

请执行以下步骤:
1. 分析错误日志，定位根本原因
2. 如果是配置问题，修复配置文件
3. 如果是依赖问题，说明需要安装什么
4. 提供修复建议

注意: 只修复明确的问题，不要做不必要的改动。"

    # 调用 Claude Code CLI
    local fix_result=""
    local retry=0

    while [[ $retry -lt $MAX_RETRIES ]]; do
        log "Attempt $((retry + 1))/$MAX_RETRIES: Running Claude Code..."

        if fix_result=$(timeout $CLAUDE_TIMEOUT claude -p "$fix_prompt" --allowedTools Read,Write,Edit 2>&1); then
            log "Claude Code completed successfully"
            log "Result: $fix_result"
        else
            log "Claude Code failed or timed out"
            fix_result="Claude Code 执行失败或超时"
        fi

        # 重启 Gateway
        restart_gateway

        # 检查健康状态
        if check_health; then
            log "Gateway is healthy!"
            notify_result "success" $((retry + 1)) "$errors" "$fix_result"
            exit 0
        fi

        retry=$((retry + 1))
        log "Gateway still unhealthy, retrying..."
    done

    # 所有重试失败
    log "All retries exhausted, fix failed"
    notify_result "failed" $MAX_RETRIES "$errors" "自动修复失败，需要人工介入"
    exit 1
}

main "$@"
```

---

## 6. 安装步骤

### 6.1 创建脚本

```bash
# 1. 复制脚本到项目目录
cp scripts/openclaw-health-check.sh /Users/ZenoWang/Documents/project/openclaw/scripts/
cp scripts/openclaw-fix.sh /Users/ZenoWang/Documents/project/openclaw/scripts/

# 2. 添加执行权限
chmod +x /Users/ZenoWang/Documents/project/openclaw/scripts/openclaw-health-check.sh
chmod +x /Users/ZenoWang/Documents/project/openclaw/scripts/openclaw-fix.sh
```

### 6.2 安装监控 LaunchAgent

```bash
# 1. 创建 plist 文件
cat > ~/Library/LaunchAgents/ai.openclaw.monitor.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/ZenoWang/Documents/project/openclaw/scripts/openclaw-health-check.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/openclaw-monitor.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-monitor.err.log</string>
</dict>
</plist>
EOF

# 2. 加载服务
launchctl load ~/Library/LaunchAgents/ai.openclaw.monitor.plist

# 3. 验证
launchctl list | grep openclaw
```

### 6.3 卸载

```bash
launchctl unload ~/Library/LaunchAgents/ai.openclaw.monitor.plist
rm ~/Library/LaunchAgents/ai.openclaw.monitor.plist
```

---

## 7. 测试计划

### 7.1 单元测试

| 测试项       | 方法                               |
| ------------ | ---------------------------------- |
| 健康检查正常 | Gateway 运行时，脚本不触发修复     |
| 健康检查失败 | 手动停止 Gateway，验证修复触发     |
| flock 锁     | 并发运行修复脚本，验证只有一个执行 |
| 通知发送     | 模拟修复完成，验证 Wake Hook 调用  |

### 7.2 集成测试

```bash
# 1. 手动停止 Gateway
launchctl bootout gui/$UID/ai.openclaw.gateway

# 2. 等待30秒，观察监控日志
tail -f /tmp/openclaw-monitor.log
tail -f /tmp/openclaw-fix.log

# 3. 验证 Discord 收到通知
```

---

## 8. 风险与缓解

| 风险                 | 影响             | 缓解措施                          |
| -------------------- | ---------------- | --------------------------------- |
| Claude Code 修复失败 | Gateway 无法恢复 | MAX_RETRIES=2，失败后通知人工介入 |
| 修复脚本死锁         | 资源占用         | flock 非阻塞模式，超时退出        |
| 通知失败             | 用户不知道状态   | 日志记录，本地日志可追溯          |
| 频繁重启             | 资源消耗         | 30s 检查间隔 + flock 防并发       |

---

## 9. 参考资源

- 原始实现: `win4r/openclaw-min-bundle` (解压码: 888999)
- systemd OnFailure 适配: macOS 使用定时检查替代
- Wake Hook API: `POST /hooks/wake` → Gateway Agent

---

## 10. 变更历史

| 日期       | 版本 | 变更         |
| ---------- | ---- | ------------ |
| 2026-03-05 | 1.0  | 初始设计文档 |
