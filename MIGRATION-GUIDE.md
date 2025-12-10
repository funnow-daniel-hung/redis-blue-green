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

### 方法一：一键完整演示（推荐）

```bash
cd redis-blue-green
./scripts/quick-start.sh
# 选择选项 1 - 完整演示
```

这个脚本会自动完成：
- ✅ 启动 Redis 4.0.10 和 Valkey 8.1 实例
- ✅ 导入 10,000+ 条测试数据
- ✅ 创建 RDB 备份
- ✅ 启动 redis-shake 进行全量同步
- ✅ 测试 PSYNC 增量同步
- ✅ 验证数据一致性
- ✅ 显示详细日志

### 方法二：手动分步执行

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

#### 3️⃣ （可选）创建 RDB 备份

```bash
# 触发 RDB 备份
docker exec redis-blue redis-cli BGSAVE

# 检查备份状态
docker exec redis-blue redis-cli LASTSAVE

# 查看 RDB 文件
docker exec redis-blue ls -lh /data/dump.rdb
```

💡 **RDB 备份的用途**：
- 离线迁移：可以复制 RDB 文件到新服务器恢复
- 备份保险：在线迁移前的安全保障
- 本演示中：redis-shake 会通过 SYNC 命令自动获取 RDB

#### 4️⃣ 启动 redis-shake 同步

```bash
docker-compose --profile sync up -d redis-shake
```

查看启动日志：
```bash
docker logs redis-shake
```

#### 5️⃣ 监控同步进度

**实时查看日志**：
```bash
docker logs -f redis-shake
```

**检查同步状态**：
```bash
./scripts/check-sync.sh
```

**手动对比数据**：
```bash
# 源库键数量
docker exec redis-blue redis-cli DBSIZE

# 目标库键数量
docker exec redis-green redis-cli DBSIZE

# 对比内存使用
docker exec redis-blue redis-cli INFO memory | grep used_memory_human
docker exec redis-green redis-cli INFO memory | grep used_memory_human
```

#### 6️⃣ 测试增量同步（PSYNC）

**向源库写入新数据**：
```bash
docker exec redis-blue redis-cli SET test_sync_key "test_value_$(date +%s)"
docker exec redis-blue redis-cli LPUSH test_list "item1" "item2" "item3"
docker exec redis-blue redis-cli HSET test_hash field1 value1 field2 value2
```

**等待 2-3 秒，检查目标库**：
```bash
docker exec redis-green redis-cli GET test_sync_key
docker exec redis-green redis-cli LRANGE test_list 0 -1
docker exec redis-green redis-cli HGETALL test_hash
```

**批量测试**：
```bash
# 写入 1000 条新数据
docker exec redis-blue bash -c '
for i in {20001..21000}; do
    redis-cli SET "new_key:$i" "value_$i" > /dev/null
done
'

# 等待同步
sleep 3

# 检查键数量是否一致
docker exec redis-blue redis-cli DBSIZE
docker exec redis-green redis-cli DBSIZE
```

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
# 使用 check-sync.sh 脚本
./scripts/check-sync.sh

# 或手动对比
docker exec redis-blue redis-cli --scan | wc -l
docker exec redis-green redis-cli --scan | wc -l

# 检查具体键值
docker exec redis-blue redis-cli GET user:100:name
docker exec redis-green redis-cli GET user:100:name
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
./scripts/check-sync.sh

# 4. 停止 redis-shake
docker-compose stop redis-shake

# 5. 修改应用配置
# 将 Redis 连接地址从 localhost:6379 改为 localhost:6380

# 6. 重启应用

# 7. 验证业务正常

# 8. 停止旧 Redis
docker-compose stop redis-blue
```

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
│   ├── migration-demo.sh         # 完整演示脚本
│   ├── quick-start.sh            # 快速启动菜单
│   ├── check-sync.sh             # 检查同步状态
│   ├── test-data.sh              # 测试数据生成
│   └── view-logs.sh              # 日志查看工具
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

### 3. 只同步特定数据库

编辑 `redis-shake/shake.toml`：
```toml
[filter]
allow_db = [0, 1]  # 只同步 DB0 和 DB1
```

### 4. 过滤键名

编辑 `redis-shake/shake.toml`：
```toml
[filter]
allow_key_prefix = ["user:", "order:"]  # 只同步这些前缀的键
block_key_prefix = ["temp:", "cache:"]   # 排除这些前缀的键
```

## 监控和告警

**查看 redis-shake 状态接口**：
```bash
curl http://localhost:8001/
```

**监控脚本示例**：
```bash
#!/bin/bash
while true; do
    BLUE=$(docker exec redis-blue redis-cli DBSIZE)
    GREEN=$(docker exec redis-green redis-cli DBSIZE)
    DIFF=$((BLUE - GREEN))

    echo "$(date) - 源库: $BLUE, 目标库: $GREEN, 差异: $DIFF"

    if [ $DIFF -gt 100 ]; then
        echo "⚠️  警告：同步延迟过大！"
    fi

    sleep 10
done
```

## 技术细节

### PSYNC vs SYNC

- **SYNC**（旧协议）：每次全量同步
- **PSYNC**（新协议）：支持断点续传，只同步增量

redis-shake 优先使用 PSYNC，如果 Redis 版本不支持则降级到 SYNC。

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

现在开始你的迁移演示吧：

```bash
./scripts/quick-start.sh
```
