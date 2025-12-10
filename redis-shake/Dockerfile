FROM golang:1.21-alpine AS builder

WORKDIR /build

# 安装必要的工具
RUN apk add --no-cache git make

# 克隆 Redis-Shake 仓库（使用 v4 版本，支持更好的配置）
RUN git clone --depth 1 --branch v4.2.0 https://github.com/tair-opensource/RedisShake.git .

# 编译
RUN go mod download && \
    go build -o redis-shake ./cmd/redis-shake

# 最终镜像
FROM alpine:latest

WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache ca-certificates tzdata

# 从 builder 复制编译好的二进制文件
COPY --from=builder /build/redis-shake /app/redis-shake

# 创建日志和数据目录
RUN mkdir -p /app/logs /app/data

# 设置权限
RUN chmod +x /app/redis-shake

# 默认命令（通过配置文件启动）
CMD ["/app/redis-shake", "shake.toml"]
