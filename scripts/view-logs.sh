#!/bin/bash
# 查看各种日志

set -e

echo "======================================"
echo "Redis 蓝绿部署 - 日志查看工具"
echo "======================================"
echo ""
echo "请选择要查看的日志："
echo "1) 蓝色 Redis 日志"
echo "2) 绿色 Redis 日志"
echo "3) Redis-Shake 容器日志"
echo "4) Redis-Shake 文件日志"
echo "5) 所有日志（并行显示）"
echo "6) 退出"
echo ""

read -p "请输入选项 (1-6): " choice

cd "$(dirname "$0")/.."

case $choice in
    1)
        echo "查看蓝色 Redis 日志（Ctrl+C 退出）..."
        docker logs -f redis-blue
        ;;
    2)
        echo "查看绿色 Redis 日志（Ctrl+C 退出）..."
        docker logs -f redis-green
        ;;
    3)
        echo "查看 Redis-Shake 容器日志（Ctrl+C 退出）..."
        if docker ps | grep -q redis-shake; then
            docker logs -f redis-shake
        else
            echo "Redis-Shake 未运行"
        fi
        ;;
    4)
        echo "查看 Redis-Shake 文件日志（Ctrl+C 退出）..."
        if [ -f "redis-shake/logs/redis-shake.log" ]; then
            tail -f redis-shake/logs/redis-shake.log
        else
            echo "日志文件不存在：redis-shake/logs/redis-shake.log"
        fi
        ;;
    5)
        echo "并行查看所有日志（Ctrl+C 退出）..."
        docker-compose logs -f
        ;;
    6)
        echo "退出"
        exit 0
        ;;
    *)
        echo "无效选项"
        exit 1
        ;;
esac
