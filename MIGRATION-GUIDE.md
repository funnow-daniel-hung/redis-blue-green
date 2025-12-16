# Redis 4.0.10 → Valkey 8.1 迁移演示指南

完整的 Redis 蓝绿部署迁移环境，演示从 Redis 4.0.10 升级到 Valkey 8.1 的全流程。

## 架构说明

```
┌─────────────────┐         ┌──────────────────┐
│  Redis 4.0.10   │         │  Valkey 8.1      │
│  (蓝色/源库)     │         │  (绿色/目标库)    │
│  Port: 6379     │         │  Port: 6380      │
└────────┬────────┘         └────────▲─────────┘
         │                           │
         │    ┌──────────────────┐   │
         └────►  redis-shake     ├───┘
              │  PSYNC 同步      │
              └──────────────────┘

同步流程：
1. 全量同步 (RDB)：redis-shake 通过 SYNC/PSYNC 获取完整数据快照
2. 增量同步 (AOF)：持续接收主库写操作，实时同步新数据
```

## 快速开始

### 手动分步执行

#### 1️⃣ 启动两个 Redis 实例

```bash
docker-compose up -d redis-blue redis-green
```

验证启动成功：
```bash
docker exec redis-blue redis-cli ping
# 输出: PONG

docker exec redis-green redis-cli ping
# 输出: PONG
```

查看版本：
```bash
docker exec redis-blue redis-cli INFO SERVER | grep redis_version
# redis_version:4.0.14

docker exec redis-green redis-cli INFO SERVER | grep redis_version
# redis_version:8.1.0
```

#### 2️⃣ 向 Redis 4.0 导入测试数据

```bash
./scripts/test-data.sh
```

或手动导入：
```bash
docker exec redis-blue bash -c '
for i in {1..1000}; do
    redis-cli SET "user:$i:name" "User_$i"
    redis-cli SET "user:$i:email" "user$i@example.com"
done
'
```

验证数据：
```bash
docker exec redis-blue redis-cli DBSIZE
# 输出: (integer) 30003

docker exec redis-blue redis-cli GET user:100:name
# 输出: "User_100"
```

#### 3️⃣ 启动 redis-shake 同步

```bash
docker-compose --profile sync up -d redis-shake
```

查看启动日志：
```bash
docker logs redis-shake
```

#### 4️⃣ 查看同步日志

等待全量同步完成，查看日誌：
```bash
docker logs -f redis-shake
```

**看到以下信息表示同步完成**：
- `rdb sync done, start sync aof` - 全量同步完成
- `syncing aof, diff=[0]` - 增量同步中，差异为 0

按 `Ctrl+C` 退出日志查看。

#### 5️⃣ 测试增量同步（PSYNC）

向源库写入新数据：
```bash
docker exec redis-blue redis-cli SET test_sync_key "test_value_$(date +%s)"
```

等待 2-3 秒，检查目标库：
```bash
docker exec redis-green redis-cli GET test_sync_key
```

如果能读取到数据，说明增量同步正常。

#### 6️⃣ 数据一致性验证

使用 **redis-full-check** 进行最终验证：

```bash
./scripts/full-verify.sh
```

**验证输出示例**（成功）：
```
======================================================
验证结果摘要
======================================================

键级别差异: 0 个

✓ 数据完全一致！
```

**如果发现差异**：

```bash
# 检查同步状态
docker logs redis-shake | tail -50

# 等待同步完成
sleep 30

# 重新验证
./scripts/full-verify.sh
```

**验证通过标准**：
- ✅ 键差异 = 0
- ✅ 同步延迟 < 1 秒（通过 `docker logs redis-shake` 查看）

满足以上条件后，可以安全进行应用切换

## 理解同步原理

### redis-shake 如何工作

1. **模拟 Slave 角色**：
   - redis-shake 连接到 Redis 4.0 (源)，发送 `PSYNC ? -1` 命令
   - Redis 4.0 将 redis-shake 视为一个从库

2. **全量同步阶段 (RDB)**：
   ```
   redis-shake → PSYNC ? -1
   Redis 4.0  → +FULLRESYNC <runid> <offset>
   Redis 4.0  → [发送 RDB 快照]
   redis-shake → [解析 RDB，写入 Valkey 8.1]
   ```

3. **增量同步阶段 (AOF/PSYNC)**：
   ```
   Redis 4.0  → [持续发送写命令]
   redis-shake → [实时转发到 Valkey 8.1]
   ```

### 查看 PSYNC 日志

设置日志级别为 `debug` 可以看到更详细的 PSYNC 信息：

编辑 `redis-shake/shake.toml`：
```toml
log_level = "debug"
```

重启 redis-shake：
```bash
docker-compose restart redis-shake
docker logs -f redis-shake
```

你会看到类似的日志：
```
[INFO] start sync rdb from source: redis-blue:6379
[INFO] source psync runid: 7a8f9b2c...
[INFO] rdb syncing... received: 1.2MB
[INFO] rdb sync done, start sync aof
[INFO] aof syncing... ops: +keys=1234 ~keys=56 -keys=0
```

## 关键日志解读

### redis-shake 日志

```
[INFO] start sync rdb from source
→ 开始全量同步，接收 RDB 快照

[INFO] rdb syncing...
→ 正在接收 RDB 数据

[INFO] rdb sync done, start sync aof
→ 全量同步完成，进入增量同步模式

[INFO] sync: +keys=1234 -keys=0 ~keys=5
→ 同步统计
  +keys: 新增的键
  -keys: 删除的键
  ~keys: 更新的键
```

### Redis INFO replication

**源库 (Redis 4.0)**：
```bash
docker exec redis-blue redis-cli INFO replication
```

输出：
```
role:master
connected_slaves:1
slave0:ip=172.18.0.4,port=39876,state=online,offset=12345,lag=0
```

**目标库 (Valkey 8.1)**：
```bash
docker exec redis-green redis-cli INFO replication
```

输出：
```
role:master
connected_slaves:0
```

> 注意：Valkey 8.1 仍然是主库，redis-shake 作为客户端写入数据

## 常见问题

### Q1: 同步速度慢怎么办？

**检查网络延迟**：
```bash
docker exec redis-shake ping redis-blue
docker exec redis-shake ping redis-green
```

**调整 redis-shake 性能参数**（编辑 `shake.toml`）：
```toml
[advanced]
ncpu = 8  # 增加 CPU 核心数
pipeline_count_limit = 2048  # 增加管道大小
```

### Q2: 如何验证数据一致性？

```bash
# 使用 redis-full-check 进行完整验证
./scripts/full-verify.sh
```

### Q3: 增量同步有延迟吗？

正常情况下延迟在**几毫秒到几百毫秒**之间。

检查延迟：
```bash
# 写入带时间戳的键
docker exec redis-blue redis-cli SET "ts:$(date +%s%N)" "$(date)"

# 立即查看目标库
docker exec redis-green redis-cli KEYS "ts:*" | tail -1
docker exec redis-green redis-cli GET $(docker exec redis-green redis-cli KEYS "ts:*" | tail -1)
```

### Q4: 同步过程中可以写入数据吗？

✅ **可以！** 这是在线迁移的核心优势：

- 源库（Redis 4.0）可以正常读写
- redis-shake 通过 PSYNC 持续同步增量数据
- 不影响业务运行

### Q5: 什么时候切换到新 Redis？

**切换时机**：
1. ✅ 数据完全同步（键数量一致）
2. ✅ 增量同步延迟稳定在可接受范围
3. ✅ 业务低峰期

**切换步骤**：
```bash
# 1. 停止写入源库（应用层控制）

# 2. 等待最后的增量数据同步
sleep 5

# 3. 最终数据验证
./scripts/full-verify.sh

# 4. 停止 redis-shake
docker-compose stop redis-shake

# 5. 修改应用配置
# 将 Redis 连接地址从 localhost:6379 改为 localhost:6380

# 6. 重启应用

# 7. 验证业务正常

# 8. 停止旧 Redis
docker-compose stop redis-blue
```

### Q6: 如何回滚（Rollback）？

如果切换后发现问题，可以回滚到旧版本：

**回滚场景**：
- 新版本 Valkey 8.1 出现问题
- 业务功能不兼容
- 性能不符合预期

**回滚步骤**：

#### 1️⃣ 停止应用写入

```bash
# 停止应用，或将应用切换为只读模式
```

#### 2️⃣ 启动反向同步

```bash
# 执行回滚脚本（Green -> Blue）
./scripts/rollback.sh

# 脚本会：
# 1. 确认操作
# 2. 停止 forward 同步
# 3. 启动 rollback 同步（使用 rollback.toml）
# 4. 显示同步日志
```

查看回滚同步状态：
```bash
docker logs -f redis-shake-rollback
```

等待看到：
- `syncing aof, diff=[0]` - 回滚同步完成

#### 3️⃣ 验证回滚数据一致性

```bash
# 验证 Green -> Blue 的数据一致性
./scripts/full-verify.sh rollback

# 查看结果
cat redis-full-check/results/result_rollback_*.txt

# 空文件 = 数据完全一致
```

#### 4️⃣ 切换应用回旧版本

```bash
# 停止回滚同步
docker stop redis-shake-rollback
docker rm redis-shake-rollback

# 修改应用配置
# 将 Redis 连接地址从 localhost:6380 改回 localhost:6379

# 重启应用
# 应用现在连接到 Blue (Redis 4.0)

# 验证业务正常
```

#### 5️⃣ 清理（可选）

```bash
# 如果确认不再需要 Green，可以停止
docker-compose stop redis-green

# 或完全删除 Green 的数据
docker-compose down redis-green
docker volume rm redis-blue-green_redis-green-data
```

**重要提示**：
- ⚠️  回滚会覆盖 Blue 的数据，确保 Green 有最新数据
- ⚠️  回滚前建议先备份 Blue 的数据
- ✅ 回滚使用相同的 PSYNC 机制，支持增量同步
- ✅ 可以在回滚后继续保持双向同步，随时再次切换

## 停止和清理

**停止所有服务（保留数据）**：
```bash
docker-compose down
```

**完全清理（删除数据）**：
```bash
docker-compose down -v
rm -rf data/ redis-shake/logs/
```

**只停止 redis-shake**：
```bash
docker-compose stop redis-shake
```

## 文件结构

```
redis-blue-green/
├── docker-compose.yaml           # 服务编排
├── redis-blue/redis.conf         # Redis 4.0 配置
├── redis-green/redis.conf        # Valkey 8.1 配置
├── redis-shake/
│   ├── Dockerfile                # redis-shake 镜像
│   ├── shake.toml                # 同步配置
│   └── logs/                     # 同步日志
├── scripts/
│   ├── full-verify.sh            # 数据一致性验证
│   ├── test-data.sh              # 测试数据生成
│   ├── start-redis.sh            # 启动 Redis 实例
│   ├── start-sync.sh             # 启动数据同步
│   └── stop-all.sh               # 停止所有服务
└── data/                         # 持久化数据
    ├── redis-blue/               # Redis 4.0 数据
    └── redis-green/              # Valkey 8.1 数据
```

## 进阶配置

### 1. 启用详细日志

编辑 `redis-shake/shake.toml`：
```toml
log_level = "debug"
```

### 2. 同步前清空目标库

编辑 `redis-shake/shake.toml`：
```toml
empty_db_before_sync = true
```

## 技术细节

### RDB vs AOF 同步

| 特性 | RDB | AOF (PSYNC) |
|------|-----|-------------|
| 同步类型 | 全量 | 增量 |
| 数据完整性 | 时间点快照 | 实时 |
| 性能影响 | 较大 | 较小 |
| 适用场景 | 初始同步 | 持续同步 |

redis-shake 同时使用两者：
1. 启动时通过 RDB 完成全量同步
2. 随后通过 AOF (PSYNC) 持续增量同步

## 总结

这个环境完整模拟了生产环境的 Redis 迁移流程：

✅ **零停机时间**：业务无需中断
✅ **数据一致性**：增量同步保证数据完整
✅ **版本跨越**：支持大版本升级（4.0.10 → 8.1）
✅ **可回滚**：迁移失败可快速切回旧版本
✅ **可验证**：提供完整的监控和验证工具

现在开始你的迁移演示吧，按照上面的"手动分步执行"步骤操作。
