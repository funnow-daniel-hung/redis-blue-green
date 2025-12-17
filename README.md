# Redis 蓝绿部署迁移环境

完整的 Redis 4.0.10 → Valkey 8.1 蓝绿升级方案，支持正向迁移和回滚。

## 核心功能

- ✅ **零停机迁移**：使用 redis-shake 进行在线同步（RDB + PSYNC）
- ✅ **数据验证**：使用 redis-full-check 确保数据一致性
- ✅ **支持回滚**：Green → Blue 反向同步，快速回退
- ✅ **压力测试**：redis-benchmark 高并发测试，验证 15,000 QPS 同步能力
- ✅ **容器化部署**：Docker Compose 一键启动，隔离环境
- ✅ **生产级配置**：详细的性能参数说明和调优建议

## 技术栈

| 组件 | 版本 | 用途 |
|------|------|------|
| Redis (Blue) | 4.0.10 | 源环境（旧版本） |
| Valkey (Green) | 8.1 | 目标环境（新版本） |
| Redis-Shake | v4.2.0 | 数据同步工具 |
| Redis-Full-Check | Latest | 数据一致性验证 |
| Docker | - | 容器化运行环境 |

## 架构说明

```
┌─────────────────┐         ┌──────────────────┐
│  Redis 4.0.10   │         │  Valkey 8.1      │
│  (蓝色/源库)     │ ──────> │  (绿色/目标库)    │
│  Port: 6379     │ Forward │  Port: 6380      │
└─────────────────┘         └──────────────────┘
         ↑                           │
         │        Rollback           │
         └───────────────────────────┘

同步工具：redis-shake (PSYNC 协议)
验证工具：redis-full-check
```

## 快速开始

### 前置要求

- Docker 和 Docker Compose
- 至少 2GB 可用内存
- 端口 6379 和 6380 未被占用

### 完整迁移流程

**请查看详细文档**：[MIGRATION-GUIDE.md](./MIGRATION-GUIDE.md)

该文档包含：
- ✅ 手动分步执行（6个步骤）
- ✅ 同步原理说明
- ✅ 日志解读
- ✅ 常见问题 FAQ
- ✅ 回滚操作指南

### 快速测试（5分钟）

```bash
# 0. 清理旧数据（避免重复写入导致验证失败）
docker-compose down
rm -rf data/redis-blue data/redis-green

# 1. 启动环境
docker-compose up -d redis-blue redis-green

# 2. 导入测试数据
./scripts/test-data.sh

# 3. 启动同步
docker-compose --profile sync up -d redis-shake

# 4. 验证数据一致性
./scripts/full-verify.sh

# 5. 查看结果（空文件 = 数据一致）
cat redis-full-check/results/result_forward_*.txt
```

## 配置文件说明

### Redis-Shake 配置

| 文件 | 说明 | 用途 |
|------|------|------|
| `redis-shake/shake.toml` | 默认配置 | Blue → Green |
| `redis-shake/forward.toml` | 正向同步配置 | Blue → Green |
| `redis-shake/rollback.toml` | 回滚同步配置 | Green → Blue |

**关键参数**（已在配置文件中详细说明）：
- `ncpu`：并发线程数（根据 EC2 核数调整）
- `pipeline_count_limit`：管道并发数（影响同步速度）
- `target_redis_client_max_querybuf_len`：目标端缓冲区（防止 OOM）

### Redis-Full-Check 配置

| 文件 | 说明 | 用途 |
|------|------|------|
| `redis-full-check/check.conf` | 默认配置 | 验证 Blue → Green |
| `redis-full-check/forward.conf` | 正向验证配置 | 验证 Blue → Green |
| `redis-full-check/rollback.conf` | 回滚验证配置 | 验证 Green → Blue |

## 常用命令

### 正向迁移（Blue → Green）

```bash
# 启动同步
docker-compose --profile sync up -d redis-shake

# 查看同步日志
docker logs -f redis-shake

# 验证数据一致性
./scripts/full-verify.sh
# 或
./scripts/full-verify.sh forward
```

### 回滚操作（Green → Blue）

```bash
# 执行回滚
./scripts/rollback.sh

# 验证回滚数据
./scripts/full-verify.sh rollback

# 查看结果
cat redis-full-check/results/result_rollback_*.txt
```

### 压力测试（可选）

```bash
# 执行高并发压力测试（15,000 QPS）
./scripts/stress-test.sh

# 手动启动监控（实时查看同步状态）
./scripts/monitor-sync.sh

# 查看压测结果
cat stress-test-result-*.csv

# 压测后验证数据一致性
./scripts/full-verify.sh forward
```

**测试参数**：
- 并发客户端：300
- 总请求次数：1,000,000
- 数据大小：512 Bytes
- 目标 QPS：15,000

**验收标准**：同步延迟 < 15 秒，数据 0 差异

### 监控和检查

```bash
# 连接 Redis 实例
docker exec -it redis-blue redis-cli
docker exec -it redis-green redis-cli

# 查看键数量
docker exec redis-blue redis-cli DBSIZE
docker exec redis-green redis-cli DBSIZE

# 查看日志
docker logs redis-shake
docker logs redis-blue
docker logs redis-green
```

### 停止和清理

```bash
# 停止基础服务（Redis Blue/Green）
docker-compose down

# 停止包含同步服务的所有容器
docker-compose --profile sync down

# 停止包含验证服务的所有容器
docker-compose --profile verify down

# 停止所有服务（包括所有 profile）
docker-compose --profile sync --profile verify down

# 完全清理（删除所有数据和容器）
docker-compose --profile sync --profile verify down -v
rm -rf data/ redis-shake/logs/ redis-full-check/results/
```

## 项目结构

```
redis-blue-green/
├── MIGRATION-GUIDE.md        # 📖 完整迁移指南（必读）
├── README.md                  # 本文件
├── docker-compose.yaml        # Docker Compose 配置
├── redis-blue/                # Redis 4.0.10 配置
│   └── redis.conf
├── redis-green/               # Valkey 8.1 配置
│   └── redis.conf
├── redis-shake/               # 同步工具配置
│   ├── Dockerfile
│   ├── shake.toml             # 默认配置
│   ├── forward.toml           # Blue -> Green
│   ├── rollback.toml          # Green -> Blue
│   └── logs/
├── redis-full-check/          # 验证工具配置
│   ├── Dockerfile
│   ├── check.conf             # 默认配置
│   ├── forward.conf           # 验证 Blue -> Green
│   ├── rollback.conf          # 验证 Green -> Blue
│   ├── README.md              # 工具使用说明
│   └── results/
├── data/                      # 数据持久化
│   ├── redis-blue/
│   ├── redis-green/
│   └── redis-shake/
└── scripts/                   # 操作脚本
    ├── test-data.sh           # 导入测试数据
    ├── full-verify.sh         # 数据一致性验证
    ├── rollback.sh            # 回滚脚本
    ├── monitor-sync.sh        # 实时监控同步状态
    └── stress-test.sh         # 高并发压力测试
```

## 文档导航

- **[MIGRATION-GUIDE.md](./MIGRATION-GUIDE.md)** - 完整迁移操作手册（必读）
  - 手动分步执行
  - 理解同步原理
  - 关键日志解读
  - 常见问题 FAQ
  - 回滚操作指南
  - 高并发压力测试

- **[redis-full-check/README.md](./redis-full-check/README.md)** - 数据验证工具说明
  - 配置文件详解
  - 比对模式说明
  - 结果解读

## 适用场景

本项目适合以下场景：

✅ Redis 版本升级（4.x → 7.x/8.x）
✅ 跨云迁移（自建 → AWS ElastiCache）
✅ 蓝绿部署演练
✅ 数据迁移方案验证
✅ 生产环境迁移前的测试

## 注意事项

1. **本地环境限制**
   - 本配置为测试环境，生产环境需要调整参数
   - Redis 内存限制为 256MB，可根据需要修改

2. **数据持久化**
   - 数据保存在 `./data/` 目录
   - 使用 `docker-compose down -v` 会删除所有数据

3. **版本兼容性**
   - Redis 4.0+ 支持 PSYNC 协议
   - Valkey 100% 兼容 Redis 协议
   - Redis-Shake 支持 Redis 2.8 ~ 7.x 及 Valkey

## 参考资料

- [Redis 官方文档](https://redis.io/documentation)
- [Valkey 官网](https://valkey.io/)
- [Redis-Shake GitHub](https://github.com/tair-opensource/RedisShake)
- [Redis-Full-Check GitHub](https://github.com/tair-opensource/RedisFullCheck)
- [AWS ElastiCache 蓝绿升级文档](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/engine-versions.html)

## 许可证

本项目仅供学习和测试使用。

---

**开始迁移？请查看 [MIGRATION-GUIDE.md](./MIGRATION-GUIDE.md) 获取详细步骤。**
