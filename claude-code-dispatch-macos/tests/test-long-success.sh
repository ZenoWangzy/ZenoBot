#!/usr/bin/env bash
# test-long-success.sh - 测试长任务成功场景
# 预期：start 1次，progress ≥ 2次，completion 1次

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PROJECT_ROOT}/scripts/lib/run-state.sh"
source "${PROJECT_ROOT}/scripts/hooks/notify.sh"

# 测试配置
TASK_NAME="test-long-success"
RUN_DURATION=660  # 11 分钟，应该触发 2 次进度通知
PROGRESS_INTERVAL=300  # 5 分钟

echo "=== Test: Long Task Success ==="
echo "Task: $TASK_NAME"
echo "Duration: $((RUN_DURATION / 60)) minutes"
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
"${PROJECT_ROOT}/scripts/hooks/on-start.sh" "$TASK_NAME" "$RUN_ID" "Test run for long success scenario"

# 获取输出文件
OUTPUT_FILE=$(get_output_path "$RUN_ID")

# 2. 模拟长时间运行，持续写输出
echo ""
echo "--- Step 2: Simulating long task ($((RUN_DURATION / 60)) min) ---"
START_TS=$(now_ts)
ELAPSED=0
ITERATION=0

while [[ $ELAPSED -lt $RUN_DURATION ]]; do
    ITERATION=$((ITERATION + 1))
    echo "[iteration $ITERATION] Working... elapsed=${ELAPSED}s" >> "$OUTPUT_FILE"

    # 等待 60 秒
    sleep 60

    ELAPSED=$(ts_diff "$START_TS")
    echo "Elapsed: $((ELAPSED / 60))m $((ELAPSED % 60))s"
done

echo "Task simulation complete"

# 3. 调用 Completion Hook
echo ""
echo "--- Step 3: Completion Hook ---"
"${PROJECT_ROOT}/scripts/hooks/on-complete.sh" "$RUN_ID" "Long task completed successfully after $((RUN_DURATION / 60)) minutes"

# 4. 验证
echo ""
echo "--- Step 4: Verification ---"
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

if [[ "$(json_get "$META_FILE" ".status")" == "done" ]]; then
    echo "✅ Final status: done"
else
    echo "❌ Final status not done"
    exit 1
fi

echo ""
echo "=== Test Passed ==="
