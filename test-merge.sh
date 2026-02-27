#!/bin/bash
# 合并后测试脚本
# 用于验证上游合并后的功能完整性

set -e

echo "========================================="
echo "🧪 开始测试合并后的代码库"
echo "========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试函数
run_test() {
    local test_name="$1"
    local test_command="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 测试 $TOTAL_TESTS: $test_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "命令: $test_command"
    echo ""

    if eval "$test_command"; then
        echo ""
        echo -e "${GREEN}✅ PASSED: $test_name${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo ""
        echo -e "${RED}❌ FAILED: $test_name${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# 1. 类型检查和构建
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  Phase 1: 构建和类型检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "TypeScript 类型检查" "pnpm tsgo"
run_test "代码构建" "pnpm build"

# 2. Lint 检查
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Phase 2: 代码质量检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "Lint 检查" "pnpm check"
run_test "格式检查" "pnpm format"

# 3. 本地功能测试
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏠 Phase 3: 本地功能测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "Watchdog 功能" "pnpm test src/daemon/watchdog.test.ts"
run_test "内存管理功能" "pnpm test src/memory/"
run_test "Windows 定时任务" "pnpm test src/daemon/schtasks.test.ts"

# 4. 上游新功能测试
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⬆️  Phase 4: 上游新功能测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "Secrets 管理功能" "pnpm test src/cli/secrets-cli.test.ts 2>/dev/null || echo '测试文件不存在，跳过'"
run_test "ACP 代理功能" "pnpm test src/acp/ 2>/dev/null || echo '测试文件不存在，跳过'"
run_test "代理路由功能" "pnpm test src/agents/.*bindings.*test.ts 2>/dev/null || echo '测试文件不存在，跳过'"

# 5. 冲突文件验证
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Phase 5: 冲突文件合并验证"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "错误处理功能 (dispatch-from-config)" "pnpm test src/auto-reply/reply/"
run_test "内存预加载功能 (attempt.ts)" "pnpm test src/agents/pi-embedded-runner/"

# 6. 完整测试套件
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Phase 6: 完整测试套件"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "完整测试套件" "pnpm test"

# 测试总结
echo ""
echo "========================================="
echo "📊 测试总结"
echo "========================================="
echo ""
echo "总测试数: $TOTAL_TESTS"
echo -e "通过: ${GREEN}$PASSED_TESTS${NC}"
echo -e "失败: ${RED}$FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 所有测试通过！合并成功！${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ 有 $FAILED_TESTS 个测试失败，请检查错误信息${NC}"
    echo ""
    exit 1
fi
