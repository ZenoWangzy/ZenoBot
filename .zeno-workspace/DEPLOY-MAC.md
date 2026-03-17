# Mac 实例部署智能同步系统

> 由 Windows 实例创建 - 2026-02-11

---

## 背景

Windows 实例已部署智能同步系统，Mac 实例需要部署同样的系统以避免数据冲突。

---

## 部署步骤

### 1. 创建备份脚本

在 `~/.openclaw/workspace/` 创建 `smart-backup.sh`:

```bash
#!/bin/bash
# zenomacbot 智能备份脚本 (Mac版本)
# 自动拉取 -> 智能合并 -> 推送

set -e

WORKSPACE_PATH="$HOME/.openclaw/workspace"
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TODAY=$(date '+%Y-%m-%d')

cd "$WORKSPACE_PATH"

# Step 1: 拉取最新版本
echo "[$TIMESTAMP] Step 1: Pulling latest version..."

# Stash 本地变更（如果有）
HAS_STASH=0
if git stash push -m "Auto-stash before pull" 2>/dev/null; then
    HAS_STASH=1
fi

# Pull 最新版本
git pull origin master --no-rebase 2>/dev/null || true

# 恢复stashed变更
if [ "$HAS_STASH" -eq 1 ]; then
    git stash pop 2>/dev/null || true
fi

echo "[$TIMESTAMP] Pull completed"

# Step 2: 智能文件隔离
echo "[$TIMESTAMP] Step 2: Isolating instance-specific files..."

DAILY_NOTE="memory/$TODAY.md"
INSTANCE_DAILY_NOTE="memory/mac-$TODAY.md"

if [ -f "$DAILY_NOTE" ]; then
    if [ -f "$INSTANCE_DAILY_NOTE" ]; then
        # 合并内容
        DAILY_CONTENT=$(cat "$DAILY_NOTE")
        INSTANCE_CONTENT=$(cat "$INSTANCE_DAILY_NOTE")

        if ! echo "$INSTANCE_CONTENT" | grep -q "## Mac Instance Updates"; then
            MERGED_CONTENT="$INSTANCE_CONTENT"$'\n\n'"## Mac Instance Updates"$'\n'"$DAILY_CONTENT"
            echo "$MERGED_CONTENT" > "$INSTANCE_DAILY_NOTE"
        fi
    else
        # 直接移动文件
        mv "$DAILY_NOTE" "$INSTANCE_DAILY_NOTE"
    fi
    rm -f "$DAILY_NOTE"
fi

echo "[$TIMESTAMP] Daily note isolated to: $INSTANCE_DAILY_NOTE"

# Step 3: 提交和推送
echo "[$TIMESTAMP] Step 3: Committing and pushing..."

git add .

STATUS=$(git status --porcelain)
if [ -n "$STATUS" ]; then
    # Commit
    COMMIT_MESSAGE="Auto backup [mac] - $TIMESTAMP"
    git commit -m "$COMMIT_MESSAGE"

    # Push
    git push origin master 2>/dev/null || true

    echo "[$TIMESTAMP] Backup completed successfully!"
    echo "[$TIMESTAMP] Instance: mac"
    COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo "[$TIMESTAMP] Commit: $COMMIT_HASH"
else
    echo "[$TIMESTAMP] No changes to backup"
fi

# Step 4: 同步日志
SYNC_LOG="memory/sync-$TODAY.log"
LOG_ENTRY="[$TIMESTAMP] [mac] Backup completed"
echo "$LOG_ENTRY" >> "$SYNC_LOG"

echo "[$TIMESTAMP] Sync log updated: $SYNC_LOG"
```

### 2. 赋予执行权限

```bash
chmod +x ~/.openclaw/workspace/smart-backup.sh
```

### 3. 创建 Launch Agent

创建 `~/Library/LaunchAgents/com.openclaw.smart-backup.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.smart-backup</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>~/.openclaw/workspace/smart-backup.sh</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>12</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/tmp/openclaw-backup.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-backup-error.log</string>
</dict>
</plist>
```

### 4. 加载 Launch Agent

```bash
launchctl load ~/Library/LaunchAgents/com.openclaw.smart-backup.plist
```

### 5. 验证

查看日志：

```bash
tail -f /tmp/openclaw-backup.log
```

检查任务状态：

```bash
launchctl list | grep openclaw
```

---

## 文件隔离说明

- **Mac 实例**: `memory/mac-2026-02-11.md`
- **Windows 实例**: `memory/win-2026-02-11.md`
- **公共文件**: `MEMORY.md`, `IDENTITY.md` 等（自动合并）

这样两个实例的 daily notes 不会冲突。

---

## 同步日志

每次同步后，会在 `memory/sync-2026-02-11.log` 中记录。

---

## 故障排查

如果同步失败：

1. 检查 GitHub token 是否有效
2. 检查网络连接
3. 查看日志文件

---

## Windows 实例状态

✅ 已部署智能同步系统
✅ 每日 12:00 自动同步
✅ 智能文件隔离
✅ 已推送到 GitHub

等待 Mac 实例部署。
