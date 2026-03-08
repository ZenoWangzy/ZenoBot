#!/usr/bin/env bash
# test-long-failure.sh - 测试长任务失败场景
# 预期：start 1次，progress ≥ 1次，failure 1次

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PROJECT_ROOT}/scripts/lib/run-state.sh"
source "${PROJECT_ROOT}/scripts/hooks/notify.sh"

# 测试配置
TASK_NAME="test-long-failure"
RUN_DURATION=420  # 7 分钟，应该触发 1 次进度通知
PROGRESS_INTERVAL=300  # 5 分钟
EXIT_CODE=1

echo "=== Test: Long Task Failure ==="
echo "Task: $TASK_NAME"
echo "Duration: $((RUN_DURATION / 60)) minutes"
echo "Progress interval: $((PROGRESS_INTERVAL / 60)) minutes"
echo "Exit code: $EXIT_CODE"
echo ""

# 生成 run_id
RUN_ID=$(generate_run_id "$TASK_NAME")
echo "Run ID: $RUN_ID"

# 临时覆盖进度间隔
export PROGRESS_INTERVAL_SEC=$PROGRESS_INTERVAL

# 1. 调用 Start Hook
echo ""
echo "--- Step 1: Start Hook ---"
"${PROJECT_ROOT}/scripts/hooks/on-start.sh" "$TASK_NAME" "$RUN_ID" "Test run for long failure scenario"

# 获取输出文件
OUTPUT_FILE=$(get_output_path "$RUN_ID")

# 2. 模拟长时间运行，持续写输出（包含错误）
echo ""
echo "--- Step 2: Simulating long task ($((RUN_DURATION / 60)) min) ---"
START_TS=$(now_ts)
ELAPSED=0
ITERATION=0

while [[ $ELAPSED -lt $RUN_DURATION ]]; do
    ITERATION=$((ITERATION + 1))

    if [[ $ITERATION -gt 5 ]]; then
        echo "[iteration $ITERATION] ERROR: Something went wrong! elapsed=${ELAPSED}s" >> "$OUTPUT_FILE"
    else
        echo "[iteration $ITERATION] Working... elapsed=${ELAPSED}s" >> "$OUTPUT_FILE"
    fi

    # 等待 60 秒
    sleep 60

    ELAPSED=$(ts_diff "$START_TS")
    echo "Elapsed: $((ELAPSED / 60))m $((ELAPSED % 60))s"
done

echo "Task simulation complete (with errors)"

# 3. 调用 Failure Hook
echo ""
echo "--- Step 3: Failure Hook ---"
"${PROJECT_ROOT}/scripts/hooks/on-failure.sh" "$RUN_ID" "$EXIT_CODE"

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

if [[ "$(json_get "$META_FILE" ".notify.failure_sent")" == "true" ]]; then
    echo "✅ Failure notification sent"
else
    echo "❌ Failure notification not sent"
    exit 1
fi

if [[ "$(json_get "$META_FILE" ".status")" == "failed" ]]; then
    echo "✅ Final status: failed"
else
    echo "❌ Final status not failed"
    exit 1
fi

if [[ "$(json_get "$META_FILE" ".result.exit_code")" == "$EXIT_CODE" ]]; then
    echo "✅ Exit code recorded: $EXIT_CODE"
else
    echo "❌ Exit code not recorded correctly"
    exit 1
fi

echo ""
echo "=== Test Passed ==="
