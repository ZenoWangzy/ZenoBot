#!/usr/bin/env bash
# test-short-task.sh - 测试秒完成场景
# 预期：start 1次，progress 0次，completion 1次

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PROJECT_ROOT}/scripts/lib/run-state.sh"
source "${PROJECT_ROOT}/scripts/hooks/notify.sh"

# 测试配置
TASK_NAME="test-short-task"
RUN_DURATION=10  # 10 秒
PROGRESS_INTERVAL=300  # 5 分钟

echo "=== Test: Short Task (Quick Complete) ==="
echo "Task: $TASK_NAME"
echo "Duration: ${RUN_DURATION} seconds"
echo "Progress interval: $((PROGRESS_INTERVAL / 60)) minutes"
echo ""

# 生成 run_id
RUN_ID=$(generate_run_id "$TASK_NAME")
echo "Run ID: $RUN_ID"

# 临时覆盖进度间隔
export PROGRESS_INTERVAL_SEC=$PROGRESS_INTERVAL

# 1. 调用 Start Hook
echo ""
echo "--- Step 1: Start Hook ---"
"${PROJECT_ROOT}/scripts/hooks/on-start.sh" "$TASK_NAME" "$RUN_ID" "Test run for short task scenario"

# 获取输出文件
OUTPUT_FILE=$(get_output_path "$RUN_ID")

# 2. 模拟短任务
echo ""
echo "--- Step 2: Simulating short task (${RUN_DURATION}s) ---"
echo "[1] Quick task started" >> "$OUTPUT_FILE"
sleep "$RUN_DURATION"
echo "[2] Quick task completed" >> "$OUTPUT_FILE"

echo "Task simulation complete"

# 3. 立即调用 Completion Hook（watcher 还没来得及发送进度）
echo ""
echo "--- Step 3: Completion Hook ---"
"${PROJECT_ROOT}/scripts/hooks/on-complete.sh" "$RUN_ID" "Short task completed in ${RUN_DURATION} seconds"

# 4. 等待 watcher 退出
sleep 2

# 5. 验证
echo ""
echo "--- Step 5: Verification ---"
DATA_DIR="${DATA_DIR:-${PROJECT_ROOT}/data}"
ARCHIVE_DIR="${DATA_DIR}/done/${RUN_ID}"

if [[ -d "$ARCHIVE_DIR" ]]; then
    echo "✅ Run archived to: $ARCHIVE_DIR"
else
    echo "❌ Run not archived"
    exit 1
fi

META_FILE="${ARCHIVE_DIR}/meta.json"
if [[ "$(json_get "$META_FILE" ".notify.start_sent")" == "true" ]]; then
    echo "✅ Start notification sent"
else
    echo "❌ Start notification not sent"
    exit 1
fi

if [[ "$(json_get "$META_FILE" ".notify.completion_sent")" == "true" ]]; then
    echo "✅ Completion notification sent"
else
    echo "❌ Completion notification not sent"
    exit 1
fi

# 检查没有发送进度通知（因为任务太快）
LAST_PROGRESS=$(json_get "$META_FILE" ".notify.last_progress_at")
if [[ "$LAST_PROGRESS" == "0" ]] || [[ -z "$LAST_PROGRESS" ]]; then
    echo "✅ No progress notification sent (as expected for short task)"
else
    echo "⚠️  Progress notification was sent at $(format_ts "$LAST_PROGRESS") (unexpected for short task)"
fi

if [[ "$(json_get "$META_FILE" ".status")" == "done" ]]; then
    echo "✅ Final status: done"
else
    echo "❌ Final status not done"
    exit 1
fi

echo ""
echo "=== Test Passed ==="
