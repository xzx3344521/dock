#!/bin/bash

# RustDesk Server 一键部署脚本 - 基于官方模板
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

# 生成有效的 JWT 密钥（32位base64）
JWT_KEY=$(openssl rand -base64 24 | tr -d '\n' | cut -c1-32)
echo "生成 JWT 密钥: $JWT_KEY"

# 基于官方模板生成 Docker Compose 文件
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
      - RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=${JWT_KEY}
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

# 预生成密钥对（解决密钥无效问题）
echo "预生成密钥对..."
if ! docker run --rm -v /data/rustdesk/server:/data lejianwen/rustdesk-server-s6:latest genkeypair 2>/dev/null; then
    echo "使用备选方法生成密钥..."
    # 如果上面的方法失败，使用容器内命令生成
    docker run --rm -v /data/rustdesk/server:/data lejianwen/rustdesk-server-s6:latest /bin/bash -c "
        cd /data
        if [ ! -f id_ed25519 ]; then
            /usr/bin/rustdesk --gen-keypair
        fi
    " 2>/dev/null || true
fi

# 检查密钥是否生成成功
if [ -f "/data/rustdesk/server/id_ed25519.pub" ]; then
    PUBLIC_KEY=$(cat /data/rustdesk/server/id_ed25519.pub)
    echo "✓ 公钥生成成功: $PUBLIC_KEY"
else
    echo "⚠ 密钥生成失败，容器将自动生成"
fi

# 启动服务
echo "启动 RustDesk 服务..."
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

echo "等待服务启动..."
sleep 30

# 检查服务状态
echo "检查服务状态..."
if [ "$(docker inspect -f '{{.State.Running}}' rustdesk 2>/dev/null)" = "true" ]; then
    echo "✓ RustDesk 服务运行正常"
    
    # 获取实际使用的公钥
    if [ -f "/data/rustdesk/server/id_ed25519.pub" ]; then
        ACTUAL_PUBLIC_KEY=$(cat /data/rustdesk/server/id_ed25519.pub)
    else
        # 从容器内获取
        ACTUAL_PUBLIC_KEY=$(docker exec rustdesk cat /data/id_ed25519.pub 2>/dev/null || echo "请在容器内查看")
    fi
else
    echo "✗ 服务启动异常，查看日志..."
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        docker compose logs
    else
        docker-compose logs
    fi
    exit 1
fi

# 显示部署信息
echo ""
echo "========================================"
echo "        RustDesk 部署完成"
echo "========================================"
echo "服务器 IP: $SERVER_IP"
echo "公钥密钥: $ACTUAL_PUBLIC_KEY"
echo "JWT 密钥: $JWT_KEY"
echo "管理密码: $FIXED_PASSWORD"
echo ""
echo "服务端口:"
echo "  - API 服务: 21114"
echo "  - HBBS: 21115 (TCP)"
echo "  - HBBS: 21116 (TCP/UDP)"
echo "  - HBBR: 21117 (TCP)"
echo "  - 其他服务: 21118-21119"
echo ""
echo "客户端连接信息:"
echo "  ID 服务器: $SERVER_IP:21116"
echo "  中继服务器: $SERVER_IP:21117"
echo "  密钥: $ACTUAL_PUBLIC_KEY"
echo ""
echo "Web 管理界面:"
echo "  http://${SERVER_IP}:21114"
echo "  用户名: admin"
echo "  密码: $FIXED_PASSWORD"
echo ""
echo "管理命令:"
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    echo "  查看日志: docker compose logs -f"
    echo "  停止服务: docker compose down"
    echo "  重启服务: docker compose restart"
else
    echo "  查看日志: docker-compose logs -f"
    echo "  停止服务: docker-compose down"
    echo "  重启服务: docker-compose restart"
fi
echo "========================================"

# 保存配置信息
cat > /data/rustdesk/deploy-info.txt << EOF
RustDesk Server 部署信息
部署时间: $(date)
服务器 IP: $SERVER_IP
公钥密钥: $ACTUAL_PUBLIC_KEY
JWT 密钥: $JWT_KEY
管理密码: $FIXED_PASSWORD

客户端配置:
ID 服务器: $SERVER_IP:21116
中继服务器: $SERVER_IP:21117
密钥: $ACTUAL_PUBLIC_KEY

Web 管理界面:
地址: http://${SERVER_IP}:21114
用户名: admin
密码: $FIXED_PASSWORD
EOF

echo "配置信息已保存到: /data/rustdesk/deploy-info.txt"
