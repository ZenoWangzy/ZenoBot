# 自愈网关系统实施计划 (Self-Healing Gateway Implementation Plan)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 OpenClaw Gateway 实现 macOS LaunchAgent 监控和 Claude Code 自动修复能力。

**Architecture:** 使用两个 shell 脚本（健康检查 + 自动修复）配合 macOS LaunchAgent 实现定时监控。当检测到 Gateway 不健康时，调用 Claude Code CLI 进行智能诊断修复，并通过 Wake Hook 通知用户。

**Tech Stack:** Bash, macOS LaunchAgent, curl, flock, Claude Code CLI

---

## Task 1: 创建健康检查脚本

**Files:**

- Create: `scripts/openclaw-health-check.sh`

**Step 1: 创建脚本文件**

```bash
#!/bin/bash
# OpenClaw Gateway 健康检查脚本
#
# 用途: 每30秒由 LaunchAgent 调用，检查 Gateway 健康状态
# 行为: 健康时静默退出，不健康时调用修复脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
FIX_SCRIPT="${SCRIPT_DIR}/openclaw-fix.sh"
HEALTH_URL="http://127.0.0.1:${GATEWAY_PORT}/health"
TIMEOUT=5
LOG_FILE="/tmp/openclaw-health-check.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# 检查 Gateway 是否运行
if ! pgrep -f "openclaw.*gateway" > /dev/null 2>&1; then
    log "Gateway process not found, triggering fix..."
    "$FIX_SCRIPT"
    exit $?
fi

# 检查健康端点
if ! curl -sf --max-time "$TIMEOUT" "$HEALTH_URL" > /dev/null 2>&1; then
    log "Health check failed (port ${GATEWAY_PORT}), triggering fix..."
    "$FIX_SCRIPT"
    exit $?
fi

# 健康状态，静默退出
exit 0
```

**Step 2: 添加执行权限**

Run: `chmod +x scripts/openclaw-health-check.sh`
Expected: 无输出

**Step 3: 验证脚本语法**

Run: `bash -n scripts/openclaw-health-check.sh`
Expected: 无输出（语法正确）

**Step 4: 提交**

```bash
git add scripts/openclaw-health-check.sh
git commit -m "feat(scripts): add gateway health check script"
```

---

## Task 2: 创建自动修复脚本

**Files:**

- Create: `scripts/openclaw-fix.sh`

**Step 1: 创建脚本文件**

```bash
#!/bin/bash
# OpenClaw Gateway 自动修复脚本
#
# 用途: 当 Gateway 异常退出时，收集错误日志并调用 Claude Code 进行修复
# 行为: flock 防并发 -> 收集日志 -> Claude 修复 -> 重启 -> 通知

set -euo pipefail

# ============ 配置 ============
LOCK_FILE="/tmp/openclaw-fix.lock"
MAX_RETRIES="${OPENCLAW_FIX_MAX_RETRIES:-2}"
CLAUDE_TIMEOUT="${OPENCLAW_CLAUDE_TIMEOUT:-300}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_LABEL="ai.openclaw.gateway"
LOG_FILE="/tmp/openclaw-fix.log"
GATEWAY_ERR_LOG="$HOME/.openclaw/logs/gateway.err.log"
GATEWAY_LOG="$HOME/.openclaw/logs/gateway.log"

# ============ flock 锁 (防止并发执行) ============
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another fix is running, skipping..." >> "$LOG_FILE"
    exit 0
fi

# ============ 日志函数 ============
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# ============ 收集错误信息 ============
collect_errors() {
    local errors=""

    # 收集 Gateway 错误日志 (最后100行)
    if [[ -f "$GATEWAY_ERR_LOG" ]]; then
        errors+="=== Gateway Error Log ===\n"
        errors+="$(tail -100 "$GATEWAY_ERR_LOG" 2>/dev/null || echo "无法读取")\n\n"
    fi

    # 收集 Gateway 标准日志 (最后50行)
    if [[ -f "$GATEWAY_LOG" ]]; then
        errors+="=== Gateway Log (last 50 lines) ===\n"
        errors+="$(tail -50 "$GATEWAY_LOG" 2>/dev/null || echo "无法读取")\n\n"
    fi

    # 检查 LaunchAgent 状态
    errors+="=== LaunchAgent Status ===\n"
    errors+="$(launchctl list | grep -E "openclaw|PID" || echo "未找到相关服务")\n\n"

    # 检查端口占用
    errors+="=== Port ${GATEWAY_PORT} Status ===\n"
    errors+="$(lsof -i :${GATEWAY_PORT} 2>/dev/null || echo "端口未监听")\n\n"

    # 检查进程
    errors+="=== OpenClaw Processes ===\n"
    errors+="$(ps aux | grep -E "openclaw|OpenClaw" | grep -v grep || echo "无相关进程")\n\n"

    # 检查磁盘空间
    errors+="=== Disk Space (home) ===\n"
    errors+="$(df -h "$HOME" | tail -1)\n"

    echo -e "$errors"
}

# ============ 重启 Gateway ============
restart_gateway() {
    log "Restarting Gateway..."

    # 先尝试优雅停止
    launchctl bootout gui/$UID/$GATEWAY_LABEL 2>/dev/null || true
    sleep 2

    # 强制杀死残留进程
    pkill -9 -f "openclaw.*gateway" 2>/dev/null || true
    sleep 1

    # 启动 Gateway
    launchctl kickstart -k gui/$UID/$GATEWAY_LABEL 2>/dev/null || true
    sleep 3
}

# ============ 健康检查 ============
check_health() {
    curl -sf --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/health" > /dev/null 2>&1
}

# ============ 通知结果 ============
notify_result() {
    local status="$1"
    local retry_count="$2"
    local error_summary="$3"
    local fix_action="$4"

    # 等待 Gateway 恢复
    sleep 2

    # 截断并转义摘要
    local safe_summary
    safe_summary=$(echo "$error_summary" | head -c 300 | tr '"' "'" | tr '\n' ' ')

    local safe_action
    safe_action=$(echo "$fix_action" | head -c 500 | tr '"' "'" | tr '\n' ' ')

    local payload
    payload=$(cat <<EOF
{
  "event": "gateway_auto_fix",
  "status": "${status}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "retry_count": ${retry_count},
  "error_summary": "${safe_summary}",
  "fix_action": "${safe_action}"
}
EOF
)

    log "Sending notification (status: ${status})..."

    if curl -sf -X POST "http://127.0.0.1:${GATEWAY_PORT}/hooks/wake" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null; then
        log "Notification sent successfully"
    else
        log "Warning: Failed to send notification (Gateway may still be recovering)"
    fi
}

# ============ 主流程 ============
main() {
    log "=========================================="
    log "=== Starting auto-fix process ==="
    log "=========================================="

    local errors
    errors=$(collect_errors)

    # 构建修复提示词
    local fix_prompt="OpenClaw Gateway 异常退出，请诊断并修复问题。

## 错误信息
$errors

## 修复指南
请按以下步骤操作:

1. **分析错误日志**
   - 识别关键错误信息
   - 定位根本原因

2. **常见问题处理**
   - 配置文件语法错误: 修复 ~/.openclaw/openclaw.json
   - 端口被占用: 识别并处理冲突进程
   - 依赖缺失: 说明需要安装的包
   - 权限问题: 修复文件权限

3. **修复原则**
   - 只修复明确的问题
   - 不做不必要的改动
   - 保持配置兼容性

请开始诊断和修复。"

    local fix_result=""
    local retry=0

    while [[ $retry -lt $MAX_RETRIES ]]; do
        log "Attempt $((retry + 1))/$MAX_RETRIES: Running Claude Code..."

        # 调用 Claude Code CLI
        if fix_result=$(timeout "$CLAUDE_TIMEOUT" claude -p "$fix_prompt" --allowedTools Read,Write,Edit 2>&1); then
            log "Claude Code completed"
            log "Result preview: $(echo "$fix_result" | head -c 200)..."
        else
            local exit_code=$?
            log "Claude Code exit code: $exit_code"
            fix_result="Claude Code 执行完成 (exit: $exit_code)"
        fi

        # 重启 Gateway
        restart_gateway

        # 检查健康状态
        if check_health; then
            log "✅ Gateway is healthy!"
            notify_result "success" $((retry + 1)) "$errors" "$fix_result"
            log "=== Auto-fix completed successfully ==="
            exit 0
        fi

        retry=$((retry + 1))
        log "Gateway still unhealthy after attempt $retry, retrying..."
        sleep 2
    done

    # 所有重试失败
    log "❌ All retries exhausted, fix failed"
    notify_result "failed" $MAX_RETRIES "$errors" "自动修复失败，需要人工介入。请检查日志: $LOG_FILE"
    log "=== Auto-fix failed ==="
    exit 1
}

main "$@"
```

**Step 2: 添加执行权限**

Run: `chmod +x scripts/openclaw-fix.sh`
Expected: 无输出

**Step 3: 验证脚本语法**

Run: `bash -n scripts/openclaw-fix.sh`
Expected: 无输出（语法正确）

**Step 4: 提交**

```bash
git add scripts/openclaw-fix.sh
git commit -m "feat(scripts): add gateway auto-fix script with Claude Code integration"
```

---

## Task 3: 创建 LaunchAgent 模板

**Files:**

- Create: `scripts/launchd/ai.openclaw.monitor.plist`

**Step 1: 创建 LaunchAgent 模板目录**

Run: `mkdir -p scripts/launchd`
Expected: 无输出

**Step 2: 创建 plist 模板文件**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>__SCRIPT_PATH__</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/openclaw-monitor.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-monitor.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OPENCLAW_GATEWAY_PORT</key>
        <string>18789</string>
        <key>OPENCLAW_FIX_MAX_RETRIES</key>
        <string>2</string>
        <key>OPENCLAW_CLAUDE_TIMEOUT</key>
        <string>300</string>
    </dict>
</dict>
</plist>
```

**Step 3: 提交**

```bash
git add scripts/launchd/ai.openclaw.monitor.plist
git commit -m "feat(scripts): add LaunchAgent plist template for gateway monitor"
```

---

## Task 4: 创建安装脚本

**Files:**

- Create: `scripts/install-monitor.sh`

**Step 1: 创建安装脚本**

```bash
#!/bin/bash
# OpenClaw Gateway Monitor 安装脚本
#
# 用途: 安装/卸载 Gateway 健康监控 LaunchAgent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_NAME="ai.openclaw.monitor.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"
LAUNCHCTL_LABEL="ai.openclaw.monitor"

usage() {
    cat <<EOF
用法: $(basename "$0") [install|uninstall|status]

命令:
  install    安装 Gateway 监控 LaunchAgent
  uninstall  卸载 Gateway 监控 LaunchAgent
  status     检查监控服务状态

环境变量:
  OPENCLAW_GATEWAY_PORT   Gateway 端口 (默认: 18789)
  OPENCLAW_FIX_MAX_RETRIES  最大修复重试次数 (默认: 2)
  OPENCLAW_CLAUDE_TIMEOUT   Claude Code 超时秒数 (默认: 300)
EOF
    exit 0
}

install() {
    echo "==> Installing OpenClaw Gateway Monitor..."

    # 检查脚本是否存在
    if [[ ! -f "$SCRIPT_DIR/openclaw-health-check.sh" ]]; then
        echo "Error: openclaw-health-check.sh not found"
        exit 1
    fi

    if [[ ! -f "$SCRIPT_DIR/openclaw-fix.sh" ]]; then
        echo "Error: openclaw-fix.sh not found"
        exit 1
    fi

    # 停止旧服务（如果存在）
    launchctl bootout gui/$UID/$LAUNCHCTL_LABEL 2>/dev/null || true

    # 创建 plist 文件
    local health_script="$SCRIPT_DIR/openclaw-health-check.sh"
    local gateway_port="${OPENCLAW_GATEWAY_PORT:-18789}"
    local max_retries="${OPENCLAW_FIX_MAX_RETRIES:-2}"
    local claude_timeout="${OPENCLAW_CLAUDE_TIMEOUT:-300}"

    cat > "$PLIST_DEST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHCTL_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$health_script</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/openclaw-monitor.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-monitor.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OPENCLAW_GATEWAY_PORT</key>
        <string>$gateway_port</string>
        <key>OPENCLAW_FIX_MAX_RETRIES</key>
        <string>$max_retries</string>
        <key>OPENCLAW_CLAUDE_TIMEOUT</key>
        <string>$claude_timeout</string>
    </dict>
</dict>
</plist>
EOF

    echo "Created: $PLIST_DEST"

    # 加载服务
    launchctl load "$PLIST_DEST"

    echo "==> Installation complete!"
    echo ""
    echo "Monitor will check Gateway health every 30 seconds."
    echo ""
    echo "Logs:"
    echo "  - /tmp/openclaw-monitor.log"
    echo "  - /tmp/openclaw-monitor.err.log"
    echo "  - /tmp/openclaw-fix.log"
    echo ""
    echo "Commands:"
    echo "  Check status: $0 status"
    echo "  View logs:    tail -f /tmp/openclaw-monitor.log"
    echo "  Uninstall:    $0 uninstall"
}

uninstall() {
    echo "==> Uninstalling OpenClaw Gateway Monitor..."

    # 停止服务
    launchctl bootout gui/$UID/$LAUNCHCTL_LABEL 2>/dev/null || true

    # 删除 plist
    if [[ -f "$PLIST_DEST" ]]; then
        rm "$PLIST_DEST"
        echo "Removed: $PLIST_DEST"
    fi

    echo "==> Uninstallation complete!"
}

status() {
    echo "=== OpenClaw Gateway Monitor Status ==="
    echo ""

    # 检查 LaunchAgent
    echo "LaunchAgent:"
    if launchctl list | grep -q "$LAUNCHCTL_LABEL"; then
        launchctl list | grep "$LAUNCHCTL_LABEL"
        echo "  Status: ✅ Running"
    else
        echo "  Status: ❌ Not running"
    fi
    echo ""

    # 检查脚本
    echo "Scripts:"
    if [[ -x "$SCRIPT_DIR/openclaw-health-check.sh" ]]; then
        echo "  ✅ openclaw-health-check.sh"
    else
        echo "  ❌ openclaw-health-check.sh (not found or not executable)"
    fi

    if [[ -x "$SCRIPT_DIR/openclaw-fix.sh" ]]; then
        echo "  ✅ openclaw-fix.sh"
    else
        echo "  ❌ openclaw-fix.sh (not found or not executable)"
    fi
    echo ""

    # 检查日志
    echo "Recent logs:"
    if [[ -f "/tmp/openclaw-monitor.log" ]]; then
        echo "  Monitor (last 5 lines):"
        tail -5 /tmp/openclaw-monitor.log | sed 's/^/    /'
    fi

    if [[ -f "/tmp/openclaw-fix.log" ]]; then
        echo "  Fix (last 5 lines):"
        tail -5 /tmp/openclaw-fix.log | sed 's/^/    /'
    fi
}

case "${1:-}" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    status)
        status
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        usage
        ;;
esac
```

**Step 2: 添加执行权限**

Run: `chmod +x scripts/install-monitor.sh`
Expected: 无输出

**Step 3: 验证脚本语法**

Run: `bash -n scripts/install-monitor.sh`
Expected: 无输出

**Step 4: 提交**

```bash
git add scripts/install-monitor.sh
git commit -m "feat(scripts): add monitor installation script"
```

---

## Task 5: 更新 scripts/CLAUDE.md 文档

**Files:**

- Modify: `scripts/CLAUDE.md`

**Step 1: 更新文档，添加新脚本说明**

在 `关键脚本` 表格中添加新条目：

```markdown
| 脚本                               | 描述                           |
| ---------------------------------- | ------------------------------ |
| `scripts/openclaw-health-check.sh` | Gateway 健康检查 (每30s)       |
| `scripts/openclaw-fix.sh`          | Gateway 自动修复 (Claude Code) |
| `scripts/install-monitor.sh`       | 监控服务安装/卸载              |
```

在 `相关文件清单` 中添加：

```markdown
├── openclaw-health-check.sh # 健康检查
├── openclaw-fix.sh # 自动修复
├── install-monitor.sh # 监控安装
├── launchd/ # LaunchAgent 模板
│ └── ai.openclaw.monitor.plist
```

**Step 2: 提交**

```bash
git add scripts/CLAUDE.md
git commit -m "docs(scripts): add self-healing gateway scripts to CLAUDE.md"
```

---

## Task 6: 手动集成测试

**Files:**

- 无文件修改（验证性测试）

**Step 1: 安装监控服务**

Run: `./scripts/install-monitor.sh install`
Expected:

```
==> Installing OpenClaw Gateway Monitor...
Created: /Users/ZenoWang/Library/LaunchAgents/ai.openclaw.monitor.plist
==> Installation complete!
```

**Step 2: 验证服务状态**

Run: `./scripts/install-monitor.sh status`
Expected: 显示 LaunchAgent 运行状态

**Step 3: 查看监控日志**

Run: `tail -f /tmp/openclaw-monitor.log`
Expected: 如果 Gateway 健康，应该没有新输出（健康时静默）

**Step 4: 模拟 Gateway 故障（可选）**

Run: `launchctl bootout gui/$UID/ai.openclaw.gateway`
Expected: 30秒内监控检测到故障并触发修复

**Step 5: 查看修复日志**

Run: `tail -f /tmp/openclaw-fix.log`
Expected: 显示修复过程

---

## Task 7: 最终提交和推送

**Step 1: 检查所有变更**

Run: `git status`
Expected: 所有新文件已提交

**Step 2: 推送到远程**

Run: `git push origin main`
Expected: 成功推送

---

## 执行选项

计划已完成并保存到 `docs/plans/2026-03-05-self-healing-gateway-impl.md`。

**两种执行方式:**

**1. Subagent-Driven (本会话)** - 每个任务派发新 subagent，任务间 review，快速迭代

**2. Parallel Session (独立会话)** - 在新会话中使用 executing-plans，批量执行带检查点

**选择哪种方式？**
