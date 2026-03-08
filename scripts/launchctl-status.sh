#!/bin/bash
# OpenClaw Gateway 状态检查脚本

echo "=== OpenClaw Gateway 状态 ==="
echo ""

# 检查 LaunchAgent
echo "📋 LaunchAgent 状态:"
launchctl list | grep -E "com\.openclaw|ai\.openclaw" || echo "  未找到相关 LaunchAgent"
echo ""

# 检查进程
echo "🔄 进程状态:"
ps aux | grep -E "openclaw.*gateway|gateway.*openclaw" | grep -v grep || echo "  Gateway 未运行"
echo ""

# 检查端口
echo "🔌 端口监听:"
lsof -i :18789 2>/dev/null | grep LISTEN || echo "  端口 18789 未监听"
echo ""

# 检查 WhatsApp 连接
echo "📱 WhatsApp 连接状态:"
tail -20 /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log 2>/dev/null | grep -q "WhatsApp Web connected" && echo "  ✅ 已连接" || echo "  ❌ 未连接"
echo ""

# 显示最新日志
echo "📝 最新日志 (最后 5 行):"
tail -5 /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log 2>/dev/null || echo "  今日日志文件不存在"
