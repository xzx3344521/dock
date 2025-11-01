#!/bin/bash

# RustDesk Server 一键部署脚本 - 修复重启问题
set -e

echo "========================================"
echo "    RustDesk Server 一键部署脚本"
echo "========================================"

# 获取服务器公网 IP
SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip || echo "127.0.0.1")
echo "检测到服务器 IP: $SERVER_IP"

# 使用固定密钥
FIXED_KEY="r0cDMF1eJa9zNqnUPB8ylbEJJWZqj6OdJnOrNhmWSLU="
echo "使用固定密钥: $FIXED_KEY"

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

# 生成简化版 Docker Compose 文件（使用官方推荐配置）
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
      - ENCRYPTED_ONLY=1
      - KEY=$FIXED_KEY
      - TZ=Asia/Shanghai
    volumes:
      - /data/rustdesk/server:/data
      - /data/rustdesk/api:/root
    command: >
      sh -c "
        echo '设置服务器配置...' &&
        echo '---' > /root/config.yaml &&
        echo 'server: $SERVER_IP:21116' >> /root/config.yaml &&
        echo 'relay: $SERVER_IP:21117' >> /root/config.yaml &&
        echo 'api: http://$SERVER_IP:21114' >> /root/config.yaml &&
        echo 'key: $FIXED_KEY' >> /root/config.yaml &&
        echo '启动服务...' &&
        /start.sh
      "
EOF

echo "Docker Compose 文件已生成"

# 直接使用 docker run 命令（更稳定）
echo "启动 RustDesk 服务..."
docker run -d \
  --name rustdesk-server \
  --restart unless-stopped \
  -p 21115:21115 \
  -p 21116:21116 \
  -p 21116:21116/udp \
  -p 21117:21117 \
  -p 21118:21118 \
  -p 21119:21119 \
  -e RELAY_IP=$SERVER_IP \
  -e SERVER_IP=$SERVER_IP \
  -e ENCRYPTED_ONLY=1 \
  -e KEY=$FIXED_KEY \
  -e TZ=Asia/Shanghai \
  -v /data/rustdesk/server:/data \
  -v /data/rustdesk/api:/root \
  lejianwen/rustdesk-server-s6:latest

echo "等待服务启动..."
sleep 20

# 检查容器状态
echo "检查容器状态..."
if docker ps | grep -q rustdesk-server; then
    echo "✓ RustDesk 服务运行正常"
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
echo "固定密钥: $FIXED_KEY"
echo "管理密码: $FIXED_PASSWORD"
echo ""
echo "服务端口:"
echo "  - HBBS: 21115 (TCP)"
echo "  - HBBS: 21116 (TCP/UDP)"
echo "  - HBBR: 21117 (TCP)"
echo "  - 管理界面: 21118-21119"
echo ""
echo "客户端连接信息:"
echo "  ID 服务器: $SERVER_IP:21116"
echo "  中继服务器: $SERVER_IP:21117"
echo "  密钥: $FIXED_KEY"
echo ""
echo "管理命令:"
echo "  查看日志: docker logs -f rustdesk-server"
echo "  停止服务: docker stop rustdesk-server"
echo "  重启服务: docker restart rustdesk-server"
echo "  进入容器: docker exec -it rustdesk-server bash"
echo "========================================"
