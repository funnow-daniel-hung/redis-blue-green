#!/bin/bash
# 检查同步状态和数据一致性

set -e

echo "======================================"
echo "检查 Redis 同步状态"
echo "======================================"

cd "$(dirname "$0")/.."

# 检查 Redis-Shake 是否运行
if ! docker ps | grep -q redis-shake; then
    echo "警告：Redis-Shake 未运行"
    echo "如果同步已完成，这是正常的"
    echo "如果同步尚未开始，请运行：./scripts/start-sync.sh"
    echo ""
fi

# 显示两个实例的数据统计
echo "数据库键数量对比："
echo "===================="

BLUE_COUNT=$(docker exec redis-blue redis-cli DBSIZE | tr -d '\r')
GREEN_COUNT=$(docker exec redis-green redis-cli DBSIZE | tr -d '\r')

echo "蓝色 Redis 4.0: $BLUE_COUNT 个键"
echo "绿色 Valkey 7.2: $GREEN_COUNT 个键"

if [ "$BLUE_COUNT" -eq "$GREEN_COUNT" ]; then
    echo "✓ 键数量一致"
else
    DIFF=$((BLUE_COUNT - GREEN_COUNT))
    echo "⚠ 键数量差异: $DIFF"
fi

echo ""
echo "内存使用情况："
echo "===================="
echo "蓝色 Redis:"
docker exec redis-blue redis-cli INFO MEMORY | grep used_memory_human
echo "绿色 Redis:"
docker exec redis-green redis-cli INFO MEMORY | grep used_memory_human

echo ""
echo "命令执行统计："
echo "===================="
echo "蓝色 Redis:"
docker exec redis-blue redis-cli INFO STATS | grep total_commands_processed
echo "绿色 Redis:"
docker exec redis-green redis-cli INFO STATS | grep total_commands_processed

# 如果 Redis-Shake 正在运行，显示日志摘要
if docker ps | grep -q redis-shake; then
    echo ""
    echo "Redis-Shake 运行状态："
    echo "===================="
    echo "最近的日志输出："
    docker logs redis-shake --tail 20
fi

echo ""
echo "======================================"
echo "详细验证数据一致性："
echo "======================================"
echo ""
echo "抽样检查几个关键数据..."

# 检查字符串类型
echo "1. 字符串数据检查："
BLUE_VAL=$(docker exec redis-blue redis-cli GET user:1000:name 2>/dev/null || echo "")
GREEN_VAL=$(docker exec redis-green redis-cli GET user:1000:name 2>/dev/null || echo "")
echo "  user:1000:name - 蓝: $BLUE_VAL, 绿: $GREEN_VAL"
if [ "$BLUE_VAL" == "$GREEN_VAL" ]; then
    echo "  ✓ 一致"
else
    echo "  ⚠ 不一致"
fi

# 检查哈希类型
echo "2. 哈希数据检查："
BLUE_HASH=$(docker exec redis-blue redis-cli HGET product:2000 name 2>/dev/null || echo "")
GREEN_HASH=$(docker exec redis-green redis-cli HGET product:2000 name 2>/dev/null || echo "")
echo "  product:2000:name - 蓝: $BLUE_HASH, 绿: $GREEN_HASH"
if [ "$BLUE_HASH" == "$GREEN_HASH" ]; then
    echo "  ✓ 一致"
else
    echo "  ⚠ 不一致"
fi

# 检查列表类型
echo "3. 列表数据检查："
BLUE_LIST=$(docker exec redis-blue redis-cli LLEN order:queue 2>/dev/null || echo "0")
GREEN_LIST=$(docker exec redis-green redis-cli LLEN order:queue 2>/dev/null || echo "0")
echo "  order:queue 长度 - 蓝: $BLUE_LIST, 绿: $GREEN_LIST"
if [ "$BLUE_LIST" == "$GREEN_LIST" ]; then
    echo "  ✓ 一致"
else
    echo "  ⚠ 不一致"
fi

echo ""
echo "提示：要查看完整的同步日志，运行："
echo "  tail -f redis-shake/logs/redis-shake.log"
echo "或："
echo "  docker logs -f redis-shake"
