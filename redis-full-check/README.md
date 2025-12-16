# Redis-Full-Check 数据一致性验证工具

## 概述

Redis-Full-Check 用于验证 Redis 源库和目标库之间的数据一致性。

## 配置文件

编辑 `redis-full-check/check.conf` 调整验证参数：

```bash
# 源 Redis（蓝色）
SOURCE_REDIS="redis-blue:6379"

# 目标 Valkey（绿色）
TARGET_REDIS="redis-green:6379"

# 比对模式
# 1 = 全值比对（精确，慢）
# 2 = 长度比对（快速，推荐）
# 3 = 仅键比对（最快）
COMPARE_MODE=2

# 比对轮次（多轮确保一致性）
COMPARE_TIMES=3

# QPS 限制（避免影响生产）
QPS_LIMIT=5000

# 并发数
PARALLEL=10
```

## 使用方法

### 运行验证

```bash
./scripts/full-verify.sh
```

### 查看结果

```bash
# 查看最新结果
cat redis-full-check/results/result_*.txt

# 查看日志
cat redis-full-check/results/verify_*.log
```

### 结果解读

- **空文件或 0 行**：数据完全一致
- **有差异**：每行显示差异的键和类型
  - `lack_target`：目标库缺少键，需要等待同步完成
  - `lack_source`：源库缺少键（目标多余），检查是否误写入
  - `value`：值不同

## 比对模式说明

| 模式 | 说明 | 速度 | 精确度 |
|------|------|------|--------|
| 1 | 全值比对 | 慢 | 最高 |
| 2 | 长度比对（默认） | 快 | 高 |
| 3 | 仅键比对 | 最快 | 中 |

## 目录结构

```
redis-full-check/
├── Dockerfile          # 镜像构建文件
├── check.conf          # 验证配置文件
├── README.md           # 本文件
└── results/            # 验证结果目录
    ├── result_*.txt    # 差异结果文件
    └── verify_*.log    # 验证日志文件
```

## 技术细节

- **容器化部署**：使用 Docker Compose profiles，不会随主服务启动
- **自动清理**：使用 `--rm` 参数，验证完成后自动删除容器
- **Debian 基础镜像**：与 redis-shake 统一环境，确保兼容性
- **Golang 1.25**：与 redis-shake 统一版本
