#!/bin/bash
# 启动 Redis-Shake 数据同步

set -e

echo "======================================"
echo "启动 Redis-Shake 数据同步"
echo "======================================"

cd "$(dirname "$0")/.."

# 检查 Redis 实例是否运行
echo "检查 Redis 实例状态..."
if ! docker ps | grep -q redis-blue; then
    echo "错误：蓝色 Redis 未运行！请先运行 ./scripts/start-redis.sh"
    exit 1
fi

if ! docker ps | grep -q redis-green; then
    echo "错误：绿色 Redis 未运行！请先运行 ./scripts/start-redis.sh"
    exit 1
fi

echo "Redis 实例运行正常"

# 显示同步前的数据统计
echo ""
echo "同步前数据统计："
echo "蓝色 Redis 键数量："
docker exec redis-blue redis-cli DBSIZE
echo "绿色 Redis 键数量："
docker exec redis-green redis-cli DBSIZE

# 启动 Redis-Shake
echo ""
echo "启动 Redis-Shake 同步服务..."
echo "这将从 Redis 4.0.10 同步数据到 Valkey 8.1"
echo ""

# 使用 profile 启动 redis-shake
docker-compose --profile sync up -d redis-shake

# 等待同步开始
echo "等待同步启动..."
sleep 3

# 检查 Redis-Shake 状态
if docker ps | grep -q redis-shake; then
    echo ""
    echo "======================================"
    echo "Redis-Shake 同步已启动！"
    echo "======================================"
    echo ""
    echo "监控同步进度："
    echo "  docker logs -f redis-shake"
    echo ""
    echo "查看同步状态："
    echo "  ./scripts/check-sync.sh"
    echo ""
    echo "查看详细日志："
    echo "  tail -f redis-shake/logs/redis-shake.log"
else
    echo "错误：Redis-Shake 启动失败！"
    echo "查看日志："
    echo "  docker-compose --profile sync logs redis-shake"
    exit 1
fi
