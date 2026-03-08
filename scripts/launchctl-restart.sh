#!/bin/bash
# OpenClaw Gateway 重启脚本

echo "🔄 重启 OpenClaw Gateway..."

# 卸载并重新加载 LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.openclaw.gateway.plist 2>/dev/null
sleep 1
launchctl load ~/Library/LaunchAgents/com.openclaw.gateway.plist

# 等待启动
sleep 3

# 检查状态
if launchctl list | grep -q "com.openclaw.gateway"; then
    echo "✅ Gateway 已启动"
    echo ""
    echo "进程信息:"
    ps aux | grep -E "openclaw.*gateway" | grep -v grep
else
    echo "❌ Gateway 启动失败"
    echo "请检查日志: /tmp/openclaw-gateway.stderr.log"
    exit 1
fi
