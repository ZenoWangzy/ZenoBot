#!/bin/bash
# OpenClaw Gateway 停止脚本

echo "⏹ 停止 OpenClaw Gateway..."

# 卸载 LaunchAgent（会停止服务）
launchctl unload ~/Library/LaunchAgents/com.openclaw.gateway.plist

# 等待进程结束
sleep 2

# 检查是否还在运行
if ps aux | grep -q "openclaw.*gateway" | grep -v grep; then
    echo "⚠️  进程仍在运行，强制终止..."
    pkill -f "openclaw.*gateway"
fi

echo "✅ Gateway 已停止"
