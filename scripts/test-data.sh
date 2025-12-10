#!/bin/bash
# 向蓝色 Redis 写入测试数据

set -e

echo "======================================"
echo "写入测试数据到蓝色 Redis"
echo "======================================"

cd "$(dirname "$0")/.."

# 写入不同类型的测试数据
echo "1. 写入字符串类型数据..."
docker exec redis-blue redis-cli SET user:1000:name "张三"
docker exec redis-blue redis-cli SET user:1000:email "zhangsan@example.com"
docker exec redis-blue redis-cli SET user:1000:age "25"
docker exec redis-blue redis-cli SETEX session:abc123 3600 "user_session_data"

echo "2. 写入哈希类型数据..."
docker exec redis-blue redis-cli HSET product:2000 name "iPhone 15"
docker exec redis-blue redis-cli HSET product:2000 price "7999"
docker exec redis-blue redis-cli HSET product:2000 stock "100"
docker exec redis-blue redis-cli HSET product:2000 category "手机"

echo "3. 写入列表类型数据..."
docker exec redis-blue redis-cli RPUSH order:queue "order_001"
docker exec redis-blue redis-cli RPUSH order:queue "order_002"
docker exec redis-blue redis-cli RPUSH order:queue "order_003"

echo "4. 写入集合类型数据..."
docker exec redis-blue redis-cli SADD tags:tech "redis"
docker exec redis-blue redis-cli SADD tags:tech "docker"
docker exec redis-blue redis-cli SADD tags:tech "kubernetes"
docker exec redis-blue redis-cli SADD tags:tech "golang"

echo "5. 写入有序集合类型数据..."
docker exec redis-blue redis-cli ZADD leaderboard 100 "player1"
docker exec redis-blue redis-cli ZADD leaderboard 85 "player2"
docker exec redis-blue redis-cli ZADD leaderboard 92 "player3"
docker exec redis-blue redis-cli ZADD leaderboard 78 "player4"

echo "6. 批量写入数据..."
for i in {1..1000}; do
    docker exec redis-blue redis-cli SET "key:$i" "value_$i" > /dev/null
done

echo ""
echo "======================================"
echo "测试数据写入完成！"
echo "======================================"

# 显示蓝色 Redis 的数据统计
echo ""
echo "蓝色 Redis 数据统计："
docker exec redis-blue redis-cli DBSIZE
docker exec redis-blue redis-cli INFO STATS | grep total_commands_processed

echo ""
echo "可以使用以下命令查看数据："
echo "  docker exec redis-blue redis-cli KEYS '*'"
echo "  docker exec redis-blue redis-cli GET user:1000:name"
echo "  docker exec redis-blue redis-cli HGETALL product:2000"
