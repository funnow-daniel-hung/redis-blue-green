#!/bin/bash

# Redis 4.0.10 → Valkey 8.1 完整迁移演示脚本
# 演示流程：启动 → 导入数据 → RDB备份 → 恢复 → PSYNC增量同步

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_step() {
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${GREEN}[步骤 $1] $2${NC}"
    echo -e "${BLUE}===================================================${NC}"
}

log_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

wait_for_redis() {
    local container=$1
    local max_wait=30
    local count=0

    log_info "等待 $container 启动..."
    until docker exec $container redis-cli ping > /dev/null 2>&1; do
        count=$((count + 1))
        if [ $count -ge $max_wait ]; then
            echo -e "${RED}❌ $container 启动超时${NC}"
            exit 1
        fi
        sleep 1
    done
    log_success "$container 已就绪"
}

# ============================================================
# 步骤 1: 启动 Redis 4.0.10 (blue) 和 Valkey 8.1 (green)
# ============================================================
log_step "1" "启动 Redis 4.0.10 (蓝色) 和 Valkey 8.1 (绿色)"

cd "$(dirname "$0")/.."

# 停止并清理旧容器
docker-compose down -v > /dev/null 2>&1 || true
rm -rf data/ redis-shake/logs/ > /dev/null 2>&1 || true

# 启动两个 Redis 实例
docker-compose up -d redis-blue redis-green

wait_for_redis redis-blue
wait_for_redis redis-green

# 显示版本信息
echo ""
log_info "Redis 版本信息："
echo -n "  - 蓝色 (源): "
docker exec redis-blue redis-cli INFO SERVER | grep redis_version | cut -d: -f2
echo -n "  - 绿色 (目标): "
docker exec redis-green redis-cli INFO SERVER | grep redis_version | cut -d: -f2
echo ""

sleep 2

# ============================================================
# 步骤 2: 向 Redis 4.0.10 导入测试数据
# ============================================================
log_step "2" "向 Redis 4.0.10 (源) 导入测试数据"

log_info "写入 10,000 条测试数据..."

docker exec redis-blue bash -c '
for i in {1..10000}; do
    redis-cli SET "user:$i:name" "User_$i" > /dev/null
    redis-cli SET "user:$i:email" "user$i@example.com" > /dev/null
    redis-cli HSET "user:$i:profile" age $((20 + i % 50)) city "City_$((i % 100))" > /dev/null

    if [ $((i % 1000)) -eq 0 ]; then
        echo "  已写入 $i 条记录..."
    fi
done
'

# 添加一些其他数据类型
log_info "添加列表、集合、有序集合数据..."
docker exec redis-blue redis-cli LPUSH mylist "item1" "item2" "item3" > /dev/null
docker exec redis-blue redis-cli SADD myset "member1" "member2" "member3" > /dev/null
docker exec redis-blue redis-cli ZADD myzset 1 "one" 2 "two" 3 "three" > /dev/null

BLUE_KEYS=$(docker exec redis-blue redis-cli DBSIZE | tr -d '\r')
BLUE_MEMORY=$(docker exec redis-blue redis-cli INFO MEMORY | grep used_memory_human | cut -d: -f2 | tr -d '\r')

echo ""
log_success "数据导入完成"
echo "  - 键数量: $BLUE_KEYS"
echo "  - 内存使用: $BLUE_MEMORY"
echo ""

sleep 2

# ============================================================
# 步骤 3: 创建 RDB 备份
# ============================================================
log_step "3" "创建 RDB 备份（可选，用于离线迁移）"

log_info "执行 BGSAVE 命令..."
docker exec redis-blue redis-cli BGSAVE > /dev/null

# 等待 BGSAVE 完成
while true; do
    SAVE_STATUS=$(docker exec redis-blue redis-cli LASTSAVE)
    sleep 1
    NEW_SAVE_STATUS=$(docker exec redis-blue redis-cli LASTSAVE)
    if [ "$SAVE_STATUS" != "$NEW_SAVE_STATUS" ]; then
        break
    fi
    echo -n "."
done
echo ""

log_success "RDB 备份完成"
docker exec redis-blue ls -lh /data/dump.rdb

echo ""
log_info "💡 如果需要离线迁移，可以："
echo "   1. 复制 RDB 文件: docker cp redis-blue:/data/dump.rdb ./backup/"
echo "   2. 在目标服务器恢复: 将 dump.rdb 放入数据目录后重启 Redis"
echo "   3. 本演示将使用在线同步方式（redis-shake + PSYNC）"
echo ""

sleep 3

# ============================================================
# 步骤 4: 使用 redis-shake 进行在线同步（RDB + PSYNC）
# ============================================================
log_step "4" "启动 redis-shake 进行在线同步"

log_info "redis-shake 工作流程："
echo "   1. 全量同步：通过 SYNC/PSYNC 命令接收 RDB 快照"
echo "   2. 增量同步：持续接收主库的写操作（模拟从库）"
echo "   3. 实时监控：查看同步日志和状态"
echo ""

log_info "启动 redis-shake..."
docker-compose --profile sync up -d redis-shake

sleep 3

log_success "redis-shake 已启动"
echo ""

# ============================================================
# 步骤 5: 监控同步进度
# ============================================================
log_step "5" "监控同步进度"

log_info "等待全量同步完成（RDB 传输）..."

# 等待同步开始
sleep 5

# 显示初始日志
echo ""
echo "📊 redis-shake 日志："
echo "---------------------------------------------------"
docker logs redis-shake 2>&1 | tail -n 20
echo "---------------------------------------------------"
echo ""

# 检查同步状态
log_info "检查同步后的数据..."
sleep 3

GREEN_KEYS=$(docker exec redis-green redis-cli DBSIZE | tr -d '\r')
GREEN_MEMORY=$(docker exec redis-green redis-cli INFO MEMORY | grep used_memory_human | cut -d: -f2 | tr -d '\r')

echo ""
echo "📈 数据对比："
echo "   源库 (Redis 4.0.10)  - 键数量: $BLUE_KEYS, 内存: $BLUE_MEMORY"
echo "   目标库 (Valkey 8.1) - 键数量: $GREEN_KEYS, 内存: $GREEN_MEMORY"
echo ""

if [ "$BLUE_KEYS" -eq "$GREEN_KEYS" ]; then
    log_success "全量同步完成！键数量一致"
else
    log_info "正在同步中... (源: $BLUE_KEYS, 目标: $GREEN_KEYS)"
fi

echo ""
sleep 2

# ============================================================
# 步骤 6: 测试增量同步（PSYNC）
# ============================================================
log_step "6" "测试增量同步（PSYNC）"

log_info "向源库写入新数据，观察增量同步..."

echo ""
echo "💡 现在 redis-shake 已经完成全量同步，进入增量同步模式"
echo "   redis-shake 通过 PSYNC 协议持续接收主库的写操作"
echo ""

# 写入新数据
log_info "写入 1000 条新数据到 Redis 4.0.10..."
docker exec redis-blue bash -c '
for i in {20001..21000}; do
    redis-cli SET "new_user:$i" "NewUser_$i" > /dev/null
done
echo "✅ 写入完成"
'

# 等待同步
sleep 3

# 检查数据
BLUE_KEYS_NEW=$(docker exec redis-blue redis-cli DBSIZE | tr -d '\r')
GREEN_KEYS_NEW=$(docker exec redis-green redis-cli DBSIZE | tr -d '\r')

echo ""
echo "📈 增量同步后的数据对比："
echo "   源库 (Redis 4.0.10)  - 键数量: $BLUE_KEYS_NEW"
echo "   目标库 (Valkey 8.1) - 键数量: $GREEN_KEYS_NEW"
echo ""

if [ "$BLUE_KEYS_NEW" -eq "$GREEN_KEYS_NEW" ]; then
    log_success "增量同步成功！新数据已同步"
else
    log_info "同步中... 差异: $((BLUE_KEYS_NEW - GREEN_KEYS_NEW)) 个键"
fi

# 验证具体数据
log_info "验证数据一致性..."
TEST_KEY="new_user:20500"
BLUE_VALUE=$(docker exec redis-blue redis-cli GET "$TEST_KEY")
GREEN_VALUE=$(docker exec redis-green redis-cli GET "$TEST_KEY")

echo "   测试键: $TEST_KEY"
echo "   源库值: $BLUE_VALUE"
echo "   目标库值: $GREEN_VALUE"

if [ "$BLUE_VALUE" = "$GREEN_VALUE" ]; then
    log_success "数据一致性验证通过！"
else
    echo -e "${RED}❌ 数据不一致${NC}"
fi

echo ""
sleep 2

# ============================================================
# 步骤 7: 查看详细同步日志
# ============================================================
log_step "7" "查看 redis-shake 详细日志"

echo ""
echo "📋 最新同步日志："
echo "---------------------------------------------------"
docker logs redis-shake 2>&1 | tail -n 30
echo "---------------------------------------------------"
echo ""

log_info "查看日志中的关键信息："
echo ""

# 提取关键日志
if docker logs redis-shake 2>&1 | grep -q "rdb syncing"; then
    echo "✅ RDB 全量同步："
    docker logs redis-shake 2>&1 | grep "rdb" | tail -n 3
fi

if docker logs redis-shake 2>&1 | grep -q "aof syncing"; then
    echo "✅ AOF 增量同步（PSYNC）："
    docker logs redis-shake 2>&1 | grep "aof" | tail -n 3
fi

echo ""

# ============================================================
# 步骤 8: 总结和后续操作
# ============================================================
log_step "8" "迁移演示完成！"

echo ""
echo "🎉 Redis 4.0.10 → Valkey 8.1 迁移流程演示完成！"
echo ""
echo "📊 最终状态："
echo "   - Redis 4.0.10 (源): 端口 6379, 键数量: $BLUE_KEYS_NEW"
echo "   - Valkey 8.1 (目标): 端口 6380, 键数量: $GREEN_KEYS_NEW"
echo "   - redis-shake: 持续运行中（增量同步）"
echo ""
echo "🔧 后续操作："
echo ""
echo "1. 查看实时日志："
echo "   docker logs -f redis-shake"
echo ""
echo "2. 继续测试增量同步："
echo "   docker exec redis-blue redis-cli SET test_key test_value"
echo "   docker exec redis-green redis-cli GET test_key"
echo ""
echo "3. 检查同步状态："
echo "   ./scripts/check-sync.sh"
echo ""
echo "4. 监控 Redis 状态："
echo "   docker exec redis-blue redis-cli INFO replication"
echo "   docker exec redis-green redis-cli INFO replication"
echo ""
echo "5. 停止同步（准备切换）："
echo "   docker-compose stop redis-shake"
echo ""
echo "6. 切换应用到新 Valkey 8.1："
echo "   修改应用配置，将端口从 6379 改为 6380"
echo ""
echo "7. 清理环境："
echo "   docker-compose down -v"
echo ""
echo "💡 提示："
echo "   - redis-shake 使用 PSYNC 协议，模拟 Redis slave 进行同步"
echo "   - 同步过程中源库完全不受影响，可以正常读写"
echo "   - 建议在业务低峰期进行切换"
echo ""
