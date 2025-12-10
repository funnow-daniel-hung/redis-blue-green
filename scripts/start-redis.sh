#!/bin/bash
# 启动蓝色和绿色 Redis 实例

set -e

echo "======================================"
echo "启动 Redis 蓝绿部署环境"
echo "======================================"

# 进入项目目录
cd "$(dirname "$0")/.."

# 启动 Redis 实例
echo "正在启动 Redis 4.0.10（端口 6379）和 Valkey 7.2.5（端口 6380）..."
docker-compose up -d redis-blue redis-green

# 等待 Redis 实例启动
echo "等待 Redis 实例启动完成..."
sleep 5

# 检查蓝色实例状态
echo ""
echo "检查 Redis 4.0.10 实例..."
docker exec redis-blue redis-cli ping
docker exec redis-blue redis-cli INFO SERVER | grep redis_version

# 检查绿色实例状态
echo ""
echo "检查 Valkey 7.2.5 实例..."
docker exec redis-green redis-cli ping
docker exec redis-green redis-cli INFO SERVER | grep redis_version

echo ""
echo "======================================"
echo "Redis 实例启动成功！"
echo "蓝色 Redis: localhost:6379 (Redis 4.0.10)"
echo "绿色 Valkey: localhost:6380 (Valkey 7.2.5)"
echo "======================================"
