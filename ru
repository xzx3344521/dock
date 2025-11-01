#!/bin/bash

# RustDesk Server 一键部署脚本
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

# 生成随机管理密码
ADMIN_PASSWORD=$(openssl rand -base64 16 2>/dev/null || date +%s | sha256sum | base64 | head -c 16)
echo "生成的管理密码: $ADMIN_PASSWORD"

# 创建必要的目录
echo "创建数据目录..."
mkdir -p /data/rustdesk/server
mkdir -p /data/rustdesk/api

# 生成 Docker Compose 文件
cat > docker-compose.yml << EOF
version: '3'

networks:
  rustdesk-net:
    external: false

services:
  rustdesk:
    ports:
      - 21114:21114
      - 21115:21115
      - 21116:21116
      - 21116:21116/udp
      - 21117:21117
      - 21118:21118
      - 21119:21119
    image: lejianwen/rustdesk-server-s6:latest
    environment:
      - RELAY=${SERVER_IP}:21117
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=y
      - TZ=Asia/Shanghai
      # RustDesk API 配置
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${SERVER_IP}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${SERVER_IP}:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://${SERVER_IP}:21114
      - RUSTDESK_API_RUSTDESK_KEY=${FIXED_KEY}
      - RUSTDESK_API_JWT_KEY=${FIXED_KEY}
      # 其他重要配置
      - RUSTDESK_API_APP_REGISTER=false
      - RUSTDESK_API_APP_DISABLE_PWD_LOGIN=false
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=3
      - RUSTDESK_API_APP_BAN_THRESHOLD=5
      - RUSTDESK_API_GORM_TYPE=sqlite
      - RUSTDESK_API_LANG=zh-CN
      - RUSTDESK_API_APP_WEB_CLIENT=1
      - RUSTDESK_API_APP_SHOW_SWAGGER=0
    volumes:
      - /data/rustdesk/server:/data
      - /data/rustdesk/api:/app/data
    networks:
      - rustdesk-net
    restart: unless-stopped
EOF

echo "Docker Compose 文件已生成"

# 启动服务
echo "启动 RustDesk 服务..."
docker-compose up -d

# 等待服务启动
echo "等待服务启动..."
sleep 10

# 显示部署信息
echo ""
echo "========================================"
echo "        RustDesk 部署完成"
echo "========================================"
echo "服务器 IP: $SERVER_IP"
echo "固定密钥: $FIXED_KEY"
echo "管理密码: $ADMIN_PASSWORD"
echo ""
echo "服务端口:"
echo "  - API 服务: 21114"
echo "  - ID 服务: 21116"
echo "  - 中继服务: 21117"
echo ""
echo "客户端连接信息:"
echo "  ID 服务器: $SERVER_IP:21116"
echo "  中继服务器: $SERVER_IP:21117"
echo "  密钥: $FIXED_KEY"
echo ""
echo "管理命令:"
echo "  查看日志: docker-compose logs -f"
echo "  停止服务: docker-compose down"
echo "  重启服务: docker-compose restart"
echo "========================================"

# 保存配置信息到文件
cat > /data/rustdesk/deploy-info.txt << EOF
RustDesk Server 部署信息
部署时间: $(date)
服务器 IP: $SERVER_IP
固定密钥: $FIXED_KEY
管理密码: $ADMIN_PASSWORD

客户端配置:
ID 服务器: $SERVER_IP:21116
中继服务器: $SERVER_IP:21117  
密钥: $FIXED_KEY

服务状态检查:
docker-compose ps
docker-compose logs
EOF

echo "配置信息已保存到: /data/rustdesk/deploy-info.txt"
