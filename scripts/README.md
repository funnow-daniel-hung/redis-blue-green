# Scripts 目录说明

这个目录包含了所有自动化脚本，帮助你快速操作 Redis 迁移环境。

## 📂 脚本列表

### 🚀 启动类脚本

#### 1. `start-redis.sh` - 启动 Redis 实例
**功能**：启动 Redis 4.0.10 和 Valkey 8.2 两个容器

**使用**：
```bash
./scripts/start-redis.sh
```

**等价于**：
```bash
docker-compose up -d redis-blue redis-green
```

**什么时候用**：当你只想启动 Redis，不启动 redis-shake

---

#### 2. `start-sync.sh` - 启动同步
**功能**：启动 redis-shake 进行数据同步

**使用**：
```bash
./scripts/start-sync.sh
```

**等价于**：
```bash
docker-compose --profile sync up -d redis-shake
```

**什么时候用**：Redis 已经启动，现在要开始同步数据

---

#### 3. `quick-start.sh` - 快速启动菜单
**功能**：交互式菜单，让你选择要执行的操作

**使用**：
```bash
./scripts/quick-start.sh
```

**菜单选项**：
- `1` - 完整演示（自动执行所有步骤）
- `2` - 查看手动步骤说明
- `3` - 仅启动 Redis 实例
- `4` - 查看同步状态
- `5` - 停止所有服务

**什么时候用**：不确定要执行什么命令，通过菜单选择

---

### 📊 数据类脚本

#### 4. `test-data.sh` - 导入测试数据
**功能**：向 Redis 4.0.10 写入测试数据（约 1000 个键）

**使用**：
```bash
./scripts/test-data.sh
```

**会创建的数据**：
- 字符串：`user:1000:name`, `user:1000:email` 等
- 哈希：`product:2000` (包含 name, price, stock 等字段)
- 列表：`order:queue`
- 集合：`tags:tech`
- 有序集合：`leaderboard`
- 批量数据：`key:1` 到 `key:1000`

**什么时候用**：需要快速导入一些测试数据

---

### 🔍 监控类脚本

#### 5. `check-sync.sh` - 检查同步状态
**功能**：对比两个 Redis 的数据，检查同步是否完成

**使用**：
```bash
./scripts/check-sync.sh
```

**会显示**：
- 键数量对比（Redis 4.0.10 vs Valkey 8.2）
- 内存使用对比
- 命令执行统计
- redis-shake 最新日志
- 抽样数据验证（验证具体键值是否一致）

**输出示例**：
```
======================================
检查 Redis 同步状态
======================================
数据库键数量对比：
====================
蓝色 Redis: 30003 个键
绿色 Redis: 30003 个键
✓ 键数量一致
```

**什么时候用**：
- 启动同步后，想知道进度
- 验证数据是否完全一致
- 排查同步问题

---

#### 6. `view-logs.sh` - 查看日志
**功能**：交互式查看各种日志

**使用**：
```bash
./scripts/view-logs.sh
```

**菜单选项**：
- `1` - 查看 redis-shake 容器日志
- `2` - 查看 redis-shake 文件日志
- `3` - 查看 Redis 4.0.10 日志
- `4` - 查看 Valkey 8.2 日志
- `5` - 实时跟踪 redis-shake 日志

**什么时候用**：
- 查看同步详细信息
- 排查错误
- 监控实时同步

---

### 🛑 停止类脚本

#### 7. `stop-all.sh` - 停止所有服务
**功能**：停止所有容器（保留数据）

**使用**：
```bash
./scripts/stop-all.sh
```

**等价于**：
```bash
docker-compose down
```

**什么时候用**：测试完成，想停止所有服务但保留数据

---

### 🎬 完整演示脚本

#### 8. `migration-demo.sh` - 完整迁移演示
**功能**：自动执行完整的迁移流程

**使用**：
```bash
./scripts/migration-demo.sh
```

**会自动执行**：
1. 停止并清理旧容器
2. 启动 Redis 4.0.10 和 Valkey 8.2
3. 导入 10,000+ 条测试数据
4. 创建 RDB 备份
5. 启动 redis-shake 同步
6. 测试增量同步
7. 验证数据一致性
8. 显示详细日志

**执行时间**：约 3-5 分钟

**什么时候用**：
- 第一次想看完整流程
- 演示给别人看
- 快速验证环境是否正常

---

## 🎯 使用场景推荐

### 场景 1: 第一次使用，想快速看效果
```bash
./scripts/migration-demo.sh
```

### 场景 2: 想手动一步步操作
```bash
# 1. 启动 Redis
./scripts/start-redis.sh

# 2. 导入数据
./scripts/test-data.sh

# 3. 启动同步
./scripts/start-sync.sh

# 4. 检查状态
./scripts/check-sync.sh

# 5. 查看日志
./scripts/view-logs.sh
```

### 场景 3: 不确定要做什么
```bash
./scripts/quick-start.sh
# 选择菜单选项
```

### 场景 4: 只想启动环境，自己手动测试
```bash
# 1. 启动 Redis
./scripts/start-redis.sh

# 2. 手动导入数据（见手动测试步骤.md）

# 3. 启动同步
./scripts/start-sync.sh
```

### 场景 5: 排查同步问题
```bash
# 检查状态
./scripts/check-sync.sh

# 查看详细日志
./scripts/view-logs.sh
# 选项 5 - 实时跟踪日志
```

---

## 🔄 常用组合命令

### 完整流程（使用脚本）
```bash
./scripts/start-redis.sh      # 启动
./scripts/test-data.sh         # 导入数据
./scripts/start-sync.sh        # 开始同步
./scripts/check-sync.sh        # 检查状态
./scripts/stop-all.sh          # 停止
```

### 完整流程（手动命令，不用脚本）
```bash
docker-compose up -d redis-blue redis-green

# 手动导入数据（见手动测试步骤.md）

docker-compose --profile sync up -d redis-shake

docker logs -f redis-shake
```

---

## 📝 脚本 vs 手动命令对照表

| 脚本 | 等价的手动命令 |
|------|---------------|
| `./scripts/start-redis.sh` | `docker-compose up -d redis-blue redis-green` |
| `./scripts/start-sync.sh` | `docker-compose --profile sync up -d redis-shake` |
| `./scripts/stop-all.sh` | `docker-compose down` |
| `./scripts/check-sync.sh` | 手动执行多个 `docker exec` 命令对比 |
| `./scripts/view-logs.sh` | `docker logs redis-shake` |
| `./scripts/test-data.sh` | 手动执行一堆 `docker exec redis-cli` 命令 |

---

## ❓ 常见问题

### Q1: 为什么要用 docker exec？

**A**: 因为 Redis 在 Docker 容器里运行，需要通过 docker exec 执行容器内的命令。

```bash
# 容器内的 redis-cli
docker exec redis-blue redis-cli SET key value

# 等价于（手动进入容器）
docker exec -it redis-blue bash
redis-cli SET key value
exit
```

### Q2: 可以不用脚本吗？

**A**: 当然可以！所有脚本都是为了方便，你完全可以手动执行命令。

参考 `手动测试步骤.md` 文件，里面都是手动命令。

### Q3: 脚本出错怎么办？

**A**:
1. 查看错误信息
2. 检查 Docker 是否启动
3. 检查容器是否运行：`docker ps`
4. 查看容器日志：`docker logs <容器名>`
5. 手动执行等价命令

### Q4: 我想修改脚本怎么办？

**A**: 所有脚本都是 bash 脚本，可以直接编辑：

```bash
# 用你喜欢的编辑器打开
vim ./scripts/test-data.sh
# 或
code ./scripts/test-data.sh
```

---

## 🎓 学习建议

### 第一次使用
1. 先运行 `./scripts/migration-demo.sh` 看完整流程
2. 理解每一步在做什么

### 深入学习
1. 打开 `手动测试步骤.md`，手动执行每一步
2. 理解每个命令的含义
3. 尝试修改参数，看效果

### 熟练使用
1. 记住常用命令
2. 不再依赖脚本
3. 可以根据需要自定义操作

---

## 💡 提示

- 所有脚本都有执行权限（`chmod +x`）
- 脚本会自动切换到项目根目录
- 出错时会显示清晰的错误信息
- 可以随时 `Ctrl+C` 中断脚本

---

**总结**：这些脚本是为了让你更方便地操作，但**不是必须的**。你完全可以手动执行所有命令！
