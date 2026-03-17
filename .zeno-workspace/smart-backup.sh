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
git pull origin main --no-rebase 2>/dev/null || true

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
    git push origin main 2>/dev/null || true

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
