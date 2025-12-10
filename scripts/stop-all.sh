#!/bin/bash
# 停止并删除所有服务

set -e

echo "======================================"
echo "停止并删除所有服务"
echo "======================================"

cd "$(dirname "$0")/.."

# 使用 --profile sync 确保 redis-shake 也被删除
# 注意：docker-compose down 会删除容器和网络，但保留数据卷
echo "停止并删除所有容器和网络..."
docker-compose --profile sync down

echo ""
echo "======================================"
echo "所有服务已停止并删除"
echo "======================================"
echo ""
echo "如需完全清理数据，运行："
echo "  rm -rf data/ redis-shake/logs/"
echo ""
echo "重新启动："
echo "  ./scripts/start-redis.sh"
