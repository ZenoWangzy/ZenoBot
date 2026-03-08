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
