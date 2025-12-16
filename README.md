# Redis 蓝绿部署本地实验环境

这是一个完整的 Redis 蓝绿升级方案本地实验环境，使用 Docker Compose 搭建，包含：
- **蓝色 Redis**：Redis 4.0.10（旧版本）- 端口 6379
- **绿色 Valkey**：Valkey 8.1（新版本）- 端口 6380
- **Redis-Shake**：数据同步工具

## 项目结构

```
redis-blue-green/
├── docker-compose.yaml       # Docker Compose 配置
├── redis-blue/               # 蓝色 Redis 配置
│   └── redis.conf
├── redis-green/              # 绿色 Redis 配置
│   └── redis.conf
├── redis-shake/              # Redis-Shake 配置
│   ├── Dockerfile
│   ├── shake.toml            # 默认配置（forward）
│   ├── forward.toml          # 正向同步配置 (Blue -> Green)
│   ├── rollback.toml         # 回滚同步配置 (Green -> Blue)
│   └── logs/                 # 同步日志目录
├── redis-full-check/         # 数据一致性验证
│   ├── Dockerfile
│   ├── check.conf            # 默认配置（forward）
│   ├── forward.conf          # 正向验证配置
│   ├── rollback.conf         # 回滚验证配置
│   └── results/              # 验证结果目录
├── data/                     # 数据持久化目录
│   ├── redis-blue/
│   ├── redis-green/
│   └── redis-shake/
└── scripts/                  # 操作脚本
    ├── start-redis.sh        # 启动 Redis 实例
    ├── test-data.sh          # 写入测试数据
    ├── start-sync.sh         # 启动数据同步
    ├── full-verify.sh        # 数据一致性验证
    ├── rollback.sh           # 回滚脚本
    └── stop-all.sh           # 停止所有服务
```

## 快速开始

### 1. 启动 Redis 实例

```bash
cd redis-blue-green
./scripts/start-redis.sh
```

这将启动：
- 蓝色 Redis (4.0.10) 在 `localhost:6379`
- 绿色 Valkey (8.1) 在 `localhost:6380`

### 2. 写入测试数据到蓝色 Redis

```bash
./scripts/test-data.sh
```

这会向蓝色 Redis 写入各种类型的测试数据：
- 字符串（String）
- 哈希（Hash）
- 列表（List）
- 集合（Set）
- 有序集合（Sorted Set）
- 1000+ 批量键值对

### 3. 启动数据同步

```bash
./scripts/start-sync.sh
```

这将启动 Redis-Shake，开始从蓝色 Redis 同步数据到绿色 Redis。

### 4. 监控同步进度

查看 redis-shake 日志：

```bash
docker logs -f redis-shake
```

看到 `syncing aof, diff=[0]` 表示同步完成。

### 5. 验证数据一致性

使用 redis-full-check 进行完整验证：

```bash
./scripts/full-verify.sh
```

### 6. 回滚操作（Rollback）

如果切换到 Valkey 8.1 后出现问题，可以回滚：

```bash
# 执行回滚脚本（Green -> Blue）
./scripts/rollback.sh

# 验证回滚数据一致性
./scripts/full-verify.sh rollback

# 查看结果
cat redis-full-check/results/result_rollback_*.txt
```

### 7. 停止服务

```bash
# 停止所有服务（保留数据）
./scripts/stop-all.sh

# 完全清理（包括删除数据卷）
docker-compose down -v
```

## 常用命令

### 直接连接 Redis

```bash
# 连接蓝色 Redis（本地）
redis-cli -h localhost -p 6379

# 连接绿色 Redis（本地）
redis-cli -h localhost -p 6380

# 在容器内连接
docker exec -it redis-blue redis-cli
docker exec -it redis-green redis-cli
```

### 查看服务状态

```bash
# 查看运行中的容器
docker-compose ps

# 查看所有容器（包括 redis-shake）
docker-compose --profile sync ps
```

### 日志管理

```bash
# 查看所有服务日志
docker-compose logs

# 查看特定服务日志
docker logs redis-blue
docker logs redis-green
docker logs redis-shake

# 实时跟踪日志
docker logs -f redis-shake
```

## Redis-Shake 配置说明

Redis-Shake 的配置文件位于 `redis-shake/shake.toml`，关键配置项：

```toml
[sync_reader]
address = "redis-blue:6379"  # 源 Redis（蓝色）
sync_rdb = true              # 全量同步
sync_aof = true              # 增量同步

[redis_writer]
address = "redis-green:6379" # 目标 Redis（绿色）

[advanced]
log_file = "logs/redis-shake.log"
log_level = "info"
empty_db_before_sync = false  # 同步前是否清空目标库
```

### 重要参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `sync_rdb` | 是否执行全量同步 | true |
| `sync_aof` | 是否执行增量同步 | true |
| `empty_db_before_sync` | 同步前清空目标库 | false |
| `log_level` | 日志级别（debug/info/warn/error） | info |
| `pipeline_count_limit` | 管道命令数量限制 | 1024 |

## 日志说明

### Redis-Shake 日志解读

Redis-Shake 会输出详细的同步信息：

```log
[INFO] start sync rdb from source
[INFO] rdb sync done, start sync aof
[INFO] sync: +keys=1234 -keys=0 ~keys=0
```

- `+keys`: 新增的键数量
- `-keys`: 删除的键数量
- `~keys`: 更新的键数量

### 查看日志的几种方式

1. **容器标准输出**（推荐用于实时监控）
   ```bash
   docker logs -f redis-shake
   ```

2. **文件日志**（推荐用于详细分析）
   ```bash
   tail -f redis-shake/logs/redis-shake.log
   ```

## 数据验证

### 数据一致性验证

使用 **redis-full-check** 进行数据一致性校验：

```bash
# 运行验证
./scripts/full-verify.sh

# 查看结果
cat redis-full-check/results/result_*.txt
```

**验证说明**：
- 配置文件：`redis-full-check/check.conf`
- 可调整比对模式、轮次、QPS 限制等参数
- 验证结果保存为文本文件

**结果解读**：
- 空文件或 0 行：数据完全一致
- 有差异：每行显示差异的键和类型
  - `lack_target`：目标库缺少键
  - `lack_source`：源库缺少键（目标多余）
  - `value`：值不同

### 手动验证

```bash
# 1. 比较键数量
docker exec redis-blue redis-cli DBSIZE
docker exec redis-green redis-cli DBSIZE

# 2. 比较具体的键值
docker exec redis-blue redis-cli GET user:1000:name
docker exec redis-green redis-cli GET user:1000:name

# 3. 查看所有键
docker exec redis-blue redis-cli KEYS '*' | sort > blue_keys.txt
docker exec redis-green redis-cli KEYS '*' | sort > green_keys.txt
diff blue_keys.txt green_keys.txt

# 4. 内存使用对比
docker exec redis-blue redis-cli INFO MEMORY | grep used_memory_human
docker exec redis-green redis-cli INFO MEMORY | grep used_memory_human
```

## 故障排查

### 问题 1：Redis-Shake 无法启动

**症状**：执行 `start-sync.sh` 后 Redis-Shake 容器立即退出

**解决方法**：
```bash
# 查看错误日志
docker-compose --profile sync logs redis-shake

# 检查 Redis 实例是否运行
docker ps | grep redis

# 重新构建 Redis-Shake 镜像
docker-compose build redis-shake
```

### 问题 2：同步速度过慢

**可能原因**：
- 数据量过大
- 网络带宽限制
- 配置参数过于保守

**解决方法**：
编辑 `redis-shake/shake.toml`，调整以下参数：
```toml
[advanced]
pipeline_count_limit = 2048  # 增加管道数量（默认 1024）
ncpu = 8                      # 增加 CPU 核心数（默认 4）
```

然后重启同步：
```bash
docker-compose --profile sync restart redis-shake
```

### 问题 3：数据不一致

**检查方法**：
```bash
# 运行一致性检查
./scripts/full-verify.sh

# 查看 Redis-Shake 日志中的错误
docker logs redis-shake | grep -i error
```

**解决方法**：
1. 确保 Redis-Shake 仍在运行（增量同步）
2. 检查是否有写入蓝色 Redis 的新数据
3. 必要时重新启动同步

### 问题 4：端口冲突

**症状**：启动失败，提示端口已被占用

**解决方法**：
```bash
# 检查端口占用
lsof -i :6379
lsof -i :6380

# 修改 docker-compose.yaml 中的端口映射
# 例如改为 "6479:6379" 和 "6480:6379"
```

## 高级用法

### 1. 持续增量同步

Redis-Shake 支持持续增量同步，在全量同步完成后会自动切换到增量模式：

```bash
# 保持 Redis-Shake 运行
docker-compose --profile sync up -d redis-shake

# 向蓝色 Redis 写入新数据
docker exec redis-blue redis-cli SET new_key "new_value"

# 几秒后检查绿色 Redis
docker exec redis-green redis-cli GET new_key
```

### 2. 性能调优

```toml
[advanced]
# 提高并发度
pipeline_count_limit = 4096

# 增加缓冲区大小
target_redis_client_max_querybuf_len = 2147483648
target_redis_proto_max_bulk_len = 512000000

# 使用更多 CPU
ncpu = 8
```

## 测试场景

### 场景 1：基础同步测试

```bash
# 1. 启动 Redis 实例
./scripts/start-redis.sh

# 2. 写入测试数据
./scripts/test-data.sh

# 3. 启动同步
./scripts/start-sync.sh

# 4. 等待 10 秒
sleep 10

# 5. 验证数据
./scripts/full-verify.sh
```

### 场景 2：实时增量同步测试

```bash
# 1. 保持 Redis-Shake 运行
docker logs -f redis-shake &

# 2. 持续写入数据到蓝色 Redis
for i in {1..100}; do
  docker exec redis-blue redis-cli SET "realtime:$i" "value_$i"
  sleep 1
done

# 3. 实时查看绿色 Redis 的键数量变化
watch -n 1 'docker exec redis-green redis-cli DBSIZE'
```

### 场景 3：大数据量测试

```bash
# 写入 10 万条数据
for i in {1..100000}; do
  docker exec redis-blue redis-cli SET "bulk:$i" "value_$i"
done

# 验证数据
./scripts/full-verify.sh
```

## 注意事项

1. **本地环境限制**
   - 本配置为测试环境，不适合生产使用
   - Redis 内存限制为 256MB，可根据需要调整
   - 无认证配置，仅限本地网络

2. **数据持久化**
   - 数据保存在 `./data/` 目录
   - 停止容器不会丢失数据
   - 使用 `docker-compose down -v` 会删除所有数据

3. **同步完整性**
   - 全量同步完成后会自动切换到增量同步
   - 保持 Redis-Shake 运行以持续同步新数据
   - 建议在低负载时执行全量同步

4. **版本兼容性**
   - 本环境演示 Redis 4.0.10 → Valkey 8.1 的迁移
   - Valkey 100% 兼容 Redis 协议，所有 Redis 命令正常工作
   - Redis-Shake 支持 Redis 2.8 到 7.x 以及 Valkey 的所有版本

## 参考资料

- [Redis 官方文档](https://redis.io/documentation)
- [Valkey 官网](https://valkey.io/)
- [Valkey GitHub](https://github.com/valkey-io/valkey)
- [Redis-Shake GitHub](https://github.com/tair-opensource/RedisShake)
- [AWS ElastiCache 蓝绿升级文档](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/engine-versions.html)
- [Docker Compose 文档](https://docs.docker.com/compose/)

## 许可证

本项目仅供学习和测试使用。

## 问题反馈

如有问题，请检查：
1. Docker 和 Docker Compose 是否正确安装
2. 端口 6379、6380 是否被占用
3. 是否有足够的磁盘空间
4. 查看 Redis-Shake 日志获取详细错误信息
