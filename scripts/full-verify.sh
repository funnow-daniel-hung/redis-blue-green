#!/bin/bash
# Redis 数据一致性验证脚本
# 使用 redis-full-check 进行数据校验

set -e

cd "$(dirname "$0")/.."

# 读取配置文件参数（默认为 forward）
CONFIG_TYPE="${1:-forward}"
CONFIG_FILE="redis-full-check/${CONFIG_TYPE}.conf"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    echo "用法: $0 [forward|rollback]"
    echo "  forward  - 验证 Blue -> Green (默认)"
    echo "  rollback - 验证 Green -> Blue"
    exit 1
fi

# 读取配置文件
source "$CONFIG_FILE"

# 构建镜像（如果不存在）
if ! docker images | grep -q redis-full-check; then
    echo "首次运行，构建 redis-full-check 镜像（需要 3-5 分钟）..."
    docker-compose build redis-full-check
fi

# 生成时间戳文件名
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="result_${CONFIG_TYPE}_${TIMESTAMP}.txt"
LOG_FILE="verify_${CONFIG_TYPE}_${TIMESTAMP}.log"

echo "开始验证: $CONFIG_TYPE"
echo "源: $SOURCE_REDIS"
echo "目标: $TARGET_REDIS"
echo ""

# 运行验证
docker-compose run --rm redis-full-check \
  /app/redis-full-check \
  -s ${SOURCE_REDIS} \
  -t ${TARGET_REDIS} \
  --result /app/results/${RESULT_FILE} \
  -m ${COMPARE_MODE} \
  --comparetimes ${COMPARE_TIMES} \
  -q ${QPS_LIMIT} \
  --parallel ${PARALLEL} \
  --log /app/results/${LOG_FILE}

echo ""
echo "验证完成！"
echo ""
echo "结果文件: redis-full-check/results/${RESULT_FILE}"
echo "日志文件: redis-full-check/results/${LOG_FILE}"
echo ""
echo "查看结果: cat redis-full-check/results/${RESULT_FILE}"
echo ""
