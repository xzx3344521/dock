#!/bin/bash
# 最简稳定版 RustDesk 部署脚本

echo "========================================"
echo "   RustDesk Server 最简部署脚本"
echo "========================================"

SERVER_IP=$(curl -s http://checkip.amazonaws.com || hostname -I | awk '{print $1}')
KEY="r0cDMF1eJa9zNqnUPB8ylbEJJWZqj6OdJnOrNhmWSLU="
PASSWORD="3459635287"

echo "服务器 IP: $SERVER_IP"
echo "密钥: $KEY"
echo "密码: $PASSWORD"

# 清理旧容器
docker rm -f rustdesk-server 2>/dev/null || true

# 创建目录
mkdir -p /data/rustdesk/{server,api}

# 最简启动命令（只使用必要参数）
docker run -d \
  --name rustdesk-server \
  --restart unless-stopped \
  -p 21115:21115 \
  -p 21116:21116 \
  -p 21116:21116/udp \
  -p 21117:21117 \
  -e RELAY_IP=$SERVER_IP \
  -e SERVER_IP=$SERVER_IP \
  -e KEY=$KEY \
  -v /data/rustdesk/server:/data \
  lejianwen/rustdesk-server-s6:latest

echo "等待服务启动..."
sleep 30

# 检查状态
if docker ps | grep -q rustdesk-server; then
    echo "✓ 部署成功！"
    echo ""
    echo "连接信息:"
    echo "ID服务器: $SERVER_IP:21116"
    echo "中继服务器: $SERVER_IP:21117" 
    echo "密钥: $KEY"
    echo "密码: $PASSWORD"
else
    echo "✗ 部署失败，查看日志:"
    docker logs rustdesk-server
fi
