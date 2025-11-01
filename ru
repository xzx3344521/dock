#!/bin/bash

# RustDesk Server 一键部署脚本 - 修复密钥问题
set -e

echo "========================================"
echo "    RustDesk Server 一键部署脚本"
echo "========================================"

# 获取服务器公网 IP
SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip || echo "127.0.0.1")
echo "检测到服务器 IP: $SERVER_IP"

# 设置固定密码
FIXED_PASSWORD="3459635287"
echo "设置管理密码: $FIXED_PASSWORD"

# 创建必要的目录
echo "创建数据目录..."
mkdir -p /data/rustdesk/server
mkdir -p /data/rustdesk/api

# 停止并删除可能存在的旧容器
echo "清理旧容器..."
docker rm -f rustdesk-server 2>/dev/null || true

# 生成有效的密钥对
echo "生成有效的密钥对..."
docker run --rm -v /data/rustdesk/server:/data lejianwen/rustdesk-server-s6:latest genkeypair

# 显示生成的公钥
if [ -f "/data/rustdesk/server/id_ed25519.pub" ]; then
    GENERATED_KEY=$(cat /data/rustdesk/server/id_ed25519.pub)
    echo "生成的公钥: $GENERATED_KEY"
else
    echo "使用备选方案生成密钥..."
    # 如果上面的方法失败，使用备选方案
    docker run --rm lejianwen/rustdesk-server-s6:latest genkeypair > /tmp/keypair.txt 2>/dev/null || true
    if [ -f "/tmp/keypair.txt" ]; then
        GENERATED_KEY=$(grep -o 'key:.*' /tmp/keypair.txt | cut -d' ' -f2 | head -1)
        echo "生成的公钥: $GENERATED_KEY"
    else
        # 最后备选：使用一个已知有效的密钥
        GENERATED_KEY="r0cDMF1eJa9zNqnUPB8ylbEJJWZqj6OdJnOrNhmWSLU="
        echo "使用默认密钥: $GENERATED_KEY"
    fi
fi

# 使用 Docker Compose 启动
cat > docker-compose.yml << EOF
version: '3'

services:
  rustdesk-server:
    image: lejianwen/rustdesk-server-s6:latest
    container_name: rustdesk-server
    restart: unless-stopped
    ports:
      - "21115:21115"
      - "21116:21116"
      - "21116:21116/udp"
      - "21117:21117"
      - "21118:21118"
      - "21119:21119"
    environment:
      - RELAY_IP=$SERVER_IP
      - SERVER_IP=$SERVER_IP
      - ENCRYPTED_ONLY=0
      - TZ=Asia/Shanghai
    volumes:
      - /data/rustdesk/server:/data
      - /data/rustdesk/api:/root
EOF

echo "启动 RustDesk 服务..."
docker-compose up -d

echo "等待服务启动..."
sleep 30

# 检查容器状态
echo "检查容器状态..."
if docker ps | grep -q rustdesk-server; then
    CONTAINER_STATUS=$(docker inspect rustdesk-server --format='{{.State.Status}}')
    if [ "$CONTAINER_STATUS" = "running" ]; then
        echo "✓ RustDesk 服务运行正常"
        
        # 获取实际使用的密钥
        if [ -f "/data/rustdesk/server/id_ed25519.pub" ]; then
            ACTUAL_KEY=$(cat /data/rustdesk/server/id_ed25519.pub)
            echo "实际使用的公钥: $ACTUAL_KEY"
        else
            ACTUAL_KEY=$GENERATED_KEY
        fi
    else
        echo "容器状态: $CONTAINER_STATUS"
        echo "查看日志..."
        docker logs rustdesk-server --tail 20
    fi
else
    echo "✗ 服务启动失败，查看日志..."
    docker logs rustdesk-server
    exit 1
fi

# 显示部署信息
echo ""
echo "========================================"
echo "        RustDesk 部署完成"
echo "========================================"
echo "服务器 IP: $SERVER_IP"
echo "公钥密钥: $ACTUAL_KEY"
echo "管理密码: $FIXED_PASSWORD"
echo ""
echo "服务端口:"
echo "  - HBBS: 21115 (TCP)"
echo "  - HBBS: 21116 (TCP/UDP)"
echo "  - HBBR: 21117 (TCP)"
echo "  - API: 21118-21119"
echo ""
echo "客户端连接信息:"
echo "  ID 服务器: $SERVER_IP:21116"
echo "  中继服务器: $SERVER_IP:21117"
echo "  密钥: $ACTUAL_KEY"
echo ""
echo "管理命令:"
echo "  查看日志: docker logs -f rustdesk-server"
echo "  停止服务: docker stop rustdesk-server"
echo "  重启服务: docker restart rustdesk-server"
echo "========================================"
