#!/bin/bash
# Chrome with remote debugging for OpenClaw
pkill -f "Google Chrome.*remote-debugging-port=9222" 2>/dev/null
sleep 1

/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir="$HOME/chrome-openclaw" \
  > /tmp/chrome-debug.log 2>&1 &

sleep 3

# 自动生成 DevToolsActivePort（Chrome 146 不自动写）
WS_ID=$(NO_PROXY=localhost,127.0.0.1 curl -s http://127.0.0.1:9222/json/version | python3 -c "import sys,json; v=json.load(sys.stdin); print(v['webSocketDebuggerUrl'].split('9222')[1])" 2>/dev/null)
if [ -n "$WS_ID" ]; then
  printf "9222\n%s" "$WS_ID" > "$HOME/chrome-openclaw/DevToolsActivePort"
  echo "✅ Chrome debug mode ready (port 9222)"
else
  echo "❌ Chrome failed to start"
fi
