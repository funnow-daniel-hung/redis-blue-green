#!/bin/bash
# Redis 回滚脚本
# 用于将数据从 Green (Valkey 8.1) 同步回 Blue (Redis 4.0)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

echo "======================================================"
echo -e "${RED}Redis 回滚操作${NC}"
echo -e "${YELLOW}从 Valkey 8.1 (Green) 同步回 Redis 4.0 (Blue)${NC}"
echo "======================================================"
echo ""

cd "$(dirname "$0")/.."

# 确认操作
log_warning "⚠️  此操作将从 Green (Valkey 8.1) 同步数据回 Blue (Redis 4.0)"
log_warning "⚠️  Blue 的现有数据将被覆盖！"
echo ""
read -p "确定要继续吗？(输入 yes 继续): " confirm

if [ "$confirm" != "yes" ]; then
    log_info "操作已取消"
    exit 0
fi

# 检查 Redis 实例是否运行
log_info "检查 Redis 实例状态..."
if ! docker ps | grep -q redis-blue; then
    log_error "蓝色 Redis 未运行！"
    exit 1
fi

if ! docker ps | grep -q redis-green; then
    log_error "绿色 Valkey 未运行！"
    exit 1
fi

log_success "Redis 实例运行正常"
echo ""

# 停止现有的 forward 同步（如果在运行）
if docker ps | grep -q redis-shake; then
    log_info "停止现有的 forward 同步..."
    docker-compose stop redis-shake
    docker rm -f redis-shake 2>/dev/null || true
fi

# 启动回滚同步
log_info "启动回滚同步 (Green -> Blue)..."
echo ""

# 使用 rollback.toml 配置文件启动 redis-shake
docker-compose run -d --name redis-shake-rollback \
  --network redis-blue-green_redis-network \
  redis-shake \
  /app/redis-shake rollback.toml

log_success "回滚同步已启动"
echo ""

# 等待同步开始
sleep 5

# 显示同步日志
log_info "同步日志（按 Ctrl+C 退出查看）："
echo "---------------------------------------------------"
docker logs -f redis-shake-rollback

