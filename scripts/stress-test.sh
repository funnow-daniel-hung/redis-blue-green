#!/bin/bash
# Redis 高併發寫入同步壓力測試
# 目標：驗證 redis-shake 在 15,000 QPS 下是否會發生堆積或 OOM

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cd "$(dirname "$0")/.."

# ========================================
# 測試配置
# ========================================
CONCURRENT_CLIENTS=300      # 並發客戶端數量
TOTAL_REQUESTS=1000000      # 總請求次數（100萬）
DATA_SIZE=512               # 數據大小（Bytes）
RANDOM_KEYS=1000000         # 隨機 Key 數量（100萬）
TARGET_QPS=15000            # 目標 QPS
TEST_DURATION=70            # 預計測試時長（秒）

# ========================================
# 驗收標準
# ========================================
MAX_SYNC_DELAY=15           # 最大同步延遲（秒）
MAX_CPU_USAGE=60            # 最大 CPU 使用率（%）
EXPECTED_MEMORY_MB=500      # 預期記憶體增加（MB）

echo "======================================================"
echo -e "${BLUE}Redis 高併發寫入同步壓力測試${NC}"
echo "======================================================"
echo ""
echo "測試配置："
echo "  - 並發客戶端: $CONCURRENT_CLIENTS"
echo "  - 總請求次數: $TOTAL_REQUESTS"
echo "  - 數據大小: $DATA_SIZE Bytes"
echo "  - 隨機 Key 數量: $RANDOM_KEYS"
echo "  - 目標 QPS: $TARGET_QPS"
echo "  - 預計時長: ~$TEST_DURATION 秒"
echo ""
echo "驗收標準："
echo "  - 同步延遲 < $MAX_SYNC_DELAY 秒"
echo "  - CPU 使用率 < $MAX_CPU_USAGE%"
echo "  - 記憶體增加約 $EXPECTED_MEMORY_MB MB"
echo ""

# ========================================
# 步驟 1: 環境檢查
# ========================================
log_info "步驟 1: 環境檢查..."

# 檢查 Redis 實例
if ! docker ps | grep -q redis-blue; then
    log_error "redis-blue 未運行！"
    exit 1
fi

if ! docker ps | grep -q redis-green; then
    log_error "redis-green 未運行！"
    exit 1
fi

# 檢查 redis-shake
if ! docker ps | grep -q redis-shake; then
    log_error "redis-shake 未運行！請先啟動同步"
    log_info "執行: docker-compose --profile sync up -d redis-shake"
    exit 1
fi

log_success "環境檢查通過"
echo ""

# ========================================
# 步驟 2: 記錄壓測前狀態
# ========================================
log_info "步驟 2: 記錄壓測前狀態..."

BLUE_KEYS_BEFORE=$(docker exec redis-blue redis-cli DBSIZE | tr -d '\r')
GREEN_KEYS_BEFORE=$(docker exec redis-green redis-cli DBSIZE | tr -d '\r')
BLUE_MEMORY_BEFORE=$(docker exec redis-blue redis-cli INFO MEMORY | grep used_memory_human | cut -d: -f2 | tr -d '\r')
GREEN_MEMORY_BEFORE=$(docker exec redis-green redis-cli INFO MEMORY | grep used_memory_human | cut -d: -f2 | tr -d '\r')

echo "壓測前狀態："
echo "  Blue (源)  - 鍵數量: $BLUE_KEYS_BEFORE, 記憶體: $BLUE_MEMORY_BEFORE"
echo "  Green (目標) - 鍵數量: $GREEN_KEYS_BEFORE, 記憶體: $GREEN_MEMORY_BEFORE"
echo ""

# ========================================
# 步驟 3: 啟動監控（背景執行）
# ========================================
log_info "步驟 3: 啟動同步監控（背景執行）..."

MONITOR_LOG="stress-test-monitor-$(date +%Y%m%d_%H%M%S).log"
./scripts/monitor-sync.sh 2 > "$MONITOR_LOG" 2>&1 &
MONITOR_PID=$!

log_success "監控已啟動 (PID: $MONITOR_PID)，日誌: $MONITOR_LOG"
echo ""
sleep 2

# ========================================
# 步驟 4: 執行壓力測試
# ========================================
log_info "步驟 4: 執行壓力測試..."
log_warning "正在向 Blue (源) 寫入 $TOTAL_REQUESTS 次請求（$TARGET_QPS QPS）..."
echo ""

START_TIME=$(date +%s)

# 執行 redis-benchmark（使用 Docker 方式，无需本机安装 redis-benchmark）
docker exec redis-blue redis-benchmark \
    -h redis-blue \
    -p 6379 \
    -c $CONCURRENT_CLIENTS \
    -n $TOTAL_REQUESTS \
    -d $DATA_SIZE \
    -t set \
    -r $RANDOM_KEYS \
    --csv > stress-test-result-$(date +%Y%m%d_%H%M%S).csv

END_TIME=$(date +%s)
ACTUAL_DURATION=$((END_TIME - START_TIME))

echo ""
log_success "壓測完成，實際耗時: $ACTUAL_DURATION 秒"
echo ""

# ========================================
# 步驟 5: 等待同步完成
# ========================================
log_info "步驟 5: 等待同步完成..."
log_info "觀察 redis-shake 的 diff 值歸零（最多等待 $MAX_SYNC_DELAY 秒）..."
echo ""

SYNC_START_TIME=$(date +%s)
SYNC_COMPLETED=false

for i in $(seq 1 $MAX_SYNC_DELAY); do
    SHAKE_DIFF=$(docker logs redis-shake 2>&1 | tail -10 | grep "diff=" | tail -1 | grep -oP 'diff=\[\K[0-9]+' || echo "-1")

    if [[ "$SHAKE_DIFF" == "0" ]]; then
        SYNC_END_TIME=$(date +%s)
        SYNC_DELAY=$((SYNC_END_TIME - END_TIME))
        log_success "同步完成！延遲: $SYNC_DELAY 秒"
        SYNC_COMPLETED=true
        break
    fi

    echo "等待中... ($i/$MAX_SYNC_DELAY 秒) - 當前 diff: $SHAKE_DIFF"
    sleep 1
done

if [[ "$SYNC_COMPLETED" == "false" ]]; then
    log_error "同步超時！diff 未在 $MAX_SYNC_DELAY 秒內歸零"
fi

echo ""

# ========================================
# 步驟 6: 停止監控
# ========================================
kill $MONITOR_PID 2>/dev/null || true
log_info "監控已停止"
echo ""

# ========================================
# 步驟 7: 記錄壓測後狀態
# ========================================
log_info "步驟 7: 記錄壓測後狀態..."

BLUE_KEYS_AFTER=$(docker exec redis-blue redis-cli DBSIZE | tr -d '\r')
GREEN_KEYS_AFTER=$(docker exec redis-green redis-cli DBSIZE | tr -d '\r')
BLUE_MEMORY_AFTER=$(docker exec redis-blue redis-cli INFO MEMORY | grep used_memory_human | cut -d: -f2 | tr -d '\r')
GREEN_MEMORY_AFTER=$(docker exec redis-green redis-cli INFO MEMORY | grep used_memory_human | cut -d: -f2 | tr -d '\r')

echo "壓測後狀態："
echo "  Blue (源)  - 鍵數量: $BLUE_KEYS_AFTER, 記憶體: $BLUE_MEMORY_AFTER"
echo "  Green (目標) - 鍵數量: $GREEN_KEYS_AFTER, 記憶體: $GREEN_MEMORY_AFTER"
echo ""

KEY_INCREASE=$((BLUE_KEYS_AFTER - BLUE_KEYS_BEFORE))
echo "新增鍵數量: $KEY_INCREASE"
echo ""

# ========================================
# 步驟 8: 數據一致性驗證
# ========================================
log_info "步驟 8: 數據一致性驗證..."

./scripts/full-verify.sh forward

VERIFY_RESULT=$(cat redis-full-check/results/result_forward_*.txt | tail -1)
VERIFY_LINES=$(wc -l < redis-full-check/results/result_forward_*.txt | tr -d ' ')

if [[ "$VERIFY_LINES" == "0" ]]; then
    log_success "✓ 數據完全一致！"
else
    log_error "✗ 發現數據差異！"
    echo "差異詳情: $VERIFY_RESULT"
fi

echo ""

# ========================================
# 步驟 9: 測試報告
# ========================================
echo "======================================================"
echo -e "${BLUE}測試報告${NC}"
echo "======================================================"
echo ""
echo "壓測配置："
echo "  - 並發客戶端: $CONCURRENT_CLIENTS"
echo "  - 總請求次數: $TOTAL_REQUESTS"
echo "  - 實際耗時: $ACTUAL_DURATION 秒"
echo "  - 實際 QPS: $((TOTAL_REQUESTS / ACTUAL_DURATION))"
echo ""
echo "同步性能："
if [[ "$SYNC_COMPLETED" == "true" ]]; then
    echo "  - 同步延遲: $SYNC_DELAY 秒 (標準: < $MAX_SYNC_DELAY 秒) ✓"
else
    echo "  - 同步延遲: > $MAX_SYNC_DELAY 秒 (標準: < $MAX_SYNC_DELAY 秒) ✗"
fi
echo ""
echo "數據一致性："
if [[ "$VERIFY_LINES" == "0" ]]; then
    echo "  - 鍵差異: 0 ✓"
else
    echo "  - 鍵差異: $VERIFY_LINES ✗"
fi
echo ""
echo "詳細日誌："
echo "  - 監控日誌: $MONITOR_LOG"
echo "  - 壓測結果: stress-test-result-*.csv"
echo "  - 驗證結果: redis-full-check/results/result_forward_*.txt"
echo ""

# 最終判定
if [[ "$SYNC_COMPLETED" == "true" && "$VERIFY_LINES" == "0" ]]; then
    log_success "========================================="
    log_success "壓力測試通過！✓"
    log_success "========================================="
else
    log_error "========================================="
    log_error "壓力測試失敗！✗"
    log_error "========================================="
fi
