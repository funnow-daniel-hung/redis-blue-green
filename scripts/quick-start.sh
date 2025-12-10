#!/bin/bash

# 快速启动脚本 - Redis 4.0.10 → Valkey 8.2 迁移演示

cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   Redis 4.0.10 → Valkey 8.2 迁移演示环境                  ║
║   使用 RDB + PSYNC 进行数据同步                           ║
╚═══════════════════════════════════════════════════════════╝

EOF

echo "选择操作："
echo ""
echo "  1. 完整演示（推荐）- 自动执行所有步骤"
echo "  2. 手动模式 - 分步执行"
echo "  3. 仅启动 Redis 实例"
echo "  4. 查看同步状态"
echo "  5. 停止所有服务"
echo ""
read -p "请输入选项 [1-5]: " choice

case $choice in
    1)
        echo ""
        echo "🚀 开始完整演示..."
        ./scripts/migration-demo.sh
        ;;
    2)
        cat << EOF

📖 手动模式步骤：

1. 启动 Redis 实例：
   docker-compose up -d redis-blue redis-green

2. 导入测试数据：
   ./scripts/test-data.sh

3. 查看 Redis 4.0 数据：
   docker exec redis-blue redis-cli DBSIZE
   docker exec redis-blue redis-cli INFO memory | grep used_memory_human

4. 启动 redis-shake 同步：
   docker-compose --profile sync up -d redis-shake

5. 查看同步日志：
   docker logs -f redis-shake

6. 检查同步状态：
   ./scripts/check-sync.sh

7. 测试增量同步：
   docker exec redis-blue redis-cli SET new_key new_value
   sleep 2
   docker exec redis-green redis-cli GET new_key

EOF
        ;;
    3)
        echo ""
        echo "🚀 启动 Redis 4.0.10 和 Valkey 8.2..."
        cd "$(dirname "$0")/.."
        docker-compose up -d redis-blue redis-green
        echo ""
        echo "✅ 启动完成"
        echo ""
        echo "   Redis 4.0.10 (蓝色): localhost:6379"
        echo "   Valkey 8.2 (绿色): localhost:6380"
        echo ""
        ;;
    4)
        echo ""
        ./scripts/check-sync.sh
        ;;
    5)
        echo ""
        echo "🛑 停止所有服务..."
        cd "$(dirname "$0")/.."
        docker-compose down
        echo "✅ 已停止"
        ;;
    *)
        echo "❌ 无效选项"
        exit 1
        ;;
esac
