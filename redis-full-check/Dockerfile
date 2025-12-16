# 使用 Debian 基础镜像构建（CGO 兼容性更好）
FROM golang:1.25 AS builder

WORKDIR /build

# 克隆 RedisFullCheck 仓库
RUN git clone --depth 1 https://github.com/tair-opensource/RedisFullCheck.git .

# 使用官方 build.sh 编译（Debian 上 CGO 支持更好）
RUN bash build.sh

# 运行时镜像 - 使用 Debian slim
FROM debian:bookworm-slim

WORKDIR /app

# 安装必要运行时库
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# 从 builder 复制二进制文件
COPY --from=builder /build/bin/redis-full-check /app/redis-full-check

# 创建结果目录
RUN mkdir -p /app/results

# 设置权限
RUN chmod +x /app/redis-full-check

# 默认工作目录
WORKDIR /app/results

# 默认使用帮助命令
CMD ["/app/redis-full-check", "-h"]
