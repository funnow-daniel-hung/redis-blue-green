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

使用 redis-benchmark 测试大量写入的同步能力：

```bash
# 记录当前键数量
BEFORE_KEYS=$(docker exec redis-green redis-cli DBSIZE)
echo "压测前 Green 键数量: $BEFORE_KEYS"

# 执行小规模压测（10,000 次写入，50 并发，使用 100,000 个随机键）
docker exec redis-blue redis-benchmark -h redis-blue -p 6379 -c 50 -n 10000 -d 512 -t set -r 100000 --csv

# 等待 3 秒让同步完成
echo "等待同步完成..."
sleep 3

# 检查同步后的键数量
AFTER_KEYS=$(docker exec redis-green redis-cli DBSIZE)
echo "压测后 Green 键数量: $AFTER_KEYS"

# 计算增加的键数量
DIFF=$((AFTER_KEYS - BEFORE_KEYS))
echo "新增键数量: $DIFF (预期: ~10000)"

# 检查 redis-shake 同步状态
docker logs redis-shake 2>&1 | tail -5 | grep "diff="
```

**预期结果**：
- Green 键数量增加约 10,000 个
- redis-shake 日志显示 `diff=[0]`（同步延迟为 0）
- 说明增量同步正常工作

#### 6️⃣ 数据一致性验证

使用 **redis-full-check** 进行最终验证：

```bash
./scripts/full-verify.sh
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


## 停止和清理


**完全清理（删除所有数据）**：
```bash
docker-compose --profile sync --profile verify down -v
rm -rf data/ redis-shake/logs/ redis-full-check/results/
```

## 高併發壓力測試（可選）

在生產環境切換前，建議進行高併發壓力測試，驗證 redis-shake 是否能承受流量高峰。

### 測試目標

- **目標 QPS**：15,000（生產環境 1,430 QPS 的 10 倍安全係數）
- **並發客戶端**：300（覆蓋線上 234 個連線）
- **數據量**：100 萬個隨機 Key，約 500MB

### 執行壓力測試

```bash
# 執行完整壓力測試（包含監控和驗證）
./scripts/stress-test.sh
```

**腳本自動執行**：
1. ✅ 環境檢查
2. ✅ 記錄壓測前狀態
3. ✅ 啟動同步監控（背景執行）
4. ✅ 執行 redis-benchmark 壓測
5. ✅ 等待同步完成（最多 15 秒）
6. ✅ 記錄壓測後狀態
7. ✅ 數據一致性驗證
8. ✅ 生成測試報告

**測試報告示例**：
```
======================================================
測試報告
======================================================

壓測配置：
  - 並發客戶端: 300
  - 總請求次數: 1000000
  - 實際耗時: 68 秒
  - 實際 QPS: 14705

同步性能：
  - 同步延遲: 3 秒 (標準: < 15 秒) ✓

數據一致性：
  - 鍵差異: 0 ✓

=========================================
壓力測試通過！✓
=========================================
```

### 驗收標準

| 指標 | 標準 | 說明 |
|------|------|------|
| 同步延遲 | < 15 秒 | 壓測停止後，diff 值歸零時間 |
| 數據一致性 | 0 差異 | redis-full-check 驗證結果 |
| Target CPU | < 60% | 目標 Redis CPU 使用率 |
| Target 記憶體 | 約 500MB 增加 | 無 Eviction 或 OOM |

**如果測試不通過**：

1. **同步延遲過長（> 15 秒）**：
   - 調整 `redis-shake/forward.toml`：
     ```toml
     pipeline_count_limit = 4096  # 增加管道數（默認 1024）
     ncpu = 8                      # 增加 CPU 核心數
     ```

2. **目標端 CPU 過高（> 60%）**：
   - 減少 `pipeline_count_limit`
   - 檢查目標端實例大小

3. **記憶體異常**：
   - 檢查是否有 Eviction：`docker exec redis-green redis-cli INFO STATS | grep evicted`
   - 增加目標端記憶體限制


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
