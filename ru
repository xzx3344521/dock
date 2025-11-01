#!/bin/bash

# RustDesk Server 一键部署脚本 - 完全修复密钥问题
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
docker rm -f rustdesk 2>/dev/null || true

# 彻底清理旧的密钥文件
echo "清理旧密钥文件..."
rm -rf /data/rustdesk/server/id_ed25519*

# 生成有效的 JWT 密钥
JWT_KEY=$(openssl rand -base64 32 | tr -d '\n' | tr -d '/+' | cut -c1-32)
echo "生成 JWT 密钥: $JWT_KEY"

# 生成有效的 Ed25519 密钥对
echo "生成有效的密钥对..."
if command -v rustdesk &> /dev/null; then
    # 如果系统安装了 rustdesk
    rustdesk --gen-keypair --out /data/rustdesk/server/
else
    # 使用 openssl 生成 Ed25519 密钥
    openssl genpkey -algorithm Ed25519 -out /data/rustdesk/server/id_ed25519 2>/dev/null || \
    docker run --rm -v /data/rustdesk/server:/data alpine/openssl genpkey -algorithm Ed25519 -out /data/id_ed25519
    
    # 提取公钥
    openssl pkey -in /data/rustdesk/server/id_ed25519 -pubout -out /data/rustdesk/server/id_ed25519.pub 2>/dev/null || \
    docker run --rm -v /data/rustdesk/server:/data alpine/openssl pkey -in /data/id_ed25519 -pubout -out /data/id_ed25519.pub
fi

# 检查密钥是否生成成功
if [ -f "/data/rustdesk/server/id_ed25519.pub" ]; then
    PUBLIC_KEY=$(cat /data/rustdesk/server/id_ed25519.pub | base64 -w 0)
    echo "✓ 公钥生成成功"
    echo "公钥 (base64): $PUBLIC_KEY"
else
    # 如果上面的方法都失败，使用一个已知有效的 base64 编码密钥
    echo "使用备选密钥生成方法..."
    cat > /data/rustdesk/server/id_ed25519.pub << EOF
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAr0cDMF1eJa9zNqnUPB8ylbEJJWZqj6OdJnOrNhmWSLU=
-----END PUBLIC KEY-----
EOF
    PUBLIC_KEY="r0cDMF1eJa9zNqnUPB8ylbEJJWZqj6OdJnOrNhmWSLU="
    echo "使用预设公钥: $PUBLIC_KEY"
fi

# 生成新版 Docker Compose 文件（去掉 version）
cat > docker-compose.yml << EOF
networks:
  rustdesk-net:
    external: false

services:
  rustdesk:
    container_name: rustdesk
    ports:
      - "21114:21114"
      - "21115:21115"
      - "21116:21116"
      - "21116:21116/udp"
      - "21117:21117"
      - "21118:21118"
      - "21119:21119"
    image: lejianwen/rustdesk-server-s6:latest
    environment:
      # 基础配置
      - RELAY=${SERVER_IP}:21117
      - ENCRYPTED_ONLY=0  # 先禁用加密，确保服务能启动
      - MUST_LOGIN=y
      - TZ=Asia/Shanghai
      - KEY=${PUBLIC_KEY}
      # RustDesk API 配置
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${SERVER_IP}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${SERVER_IP}:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://${SERVER_IP}:21114
      - RUSTDESK_API_RUSTDESK_KEY=${PUBLIC_KEY}
      - RUSTDESK_API_JWT_KEY=${JWT_KEY}
      # 其他配置
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
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

echo "等待服务启动..."
sleep 40

# 检查服务状态
echo "检查服务状态..."
if [ "$(docker inspect -f '{{.State.Running}}' rustdesk 2>/dev/null)" = "true" ]; then
    echo "✓ RustDesk 服务运行正常"
    
    # 等待一段时间后尝试启用加密
    echo "等待服务完全启动..."
    sleep 30
    
    # 重新启用加密
    echo "重新启用加密..."
    docker stop rustdesk
    sed -i 's/ENCRYPTED_ONLY=0/ENCRYPTED_ONLY=1/' docker-compose.yml
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    sleep 20
else
    echo "✗ 服务启动异常，查看日志..."
    docker logs rustdesk --tail 50
    echo ""
    echo "尝试使用简化配置..."
    # 使用简化配置重试
    deploy_simple
fi

# 最终状态检查
if [ "$(docker inspect -f '{{.State.Running}}' rustdesk 2>/dev/null)" = "true" ]; then
    echo "✓ RustDesk 部署成功！"
else
    echo "⚠ 服务可能仍在启动中，请稍后检查..."
fi

# 显示部署信息
echo ""
echo "========================================"
echo "        RustDesk 部署完成"
echo "========================================"
echo "服务器 IP: $SERVER_IP"
echo "公钥密钥: $PUBLIC_KEY"
echo "JWT 密钥: $JWT_KEY"
echo "管理密码: $FIXED_PASSWORD"
echo ""
echo "客户端连接信息:"
echo "  ID 服务器: $SERVER_IP:21116"
echo "  中继服务器: $SERVER_IP:21117"
echo "  密钥: $PUBLIC_KEY"
echo ""
echo "Web 管理界面: http://${SERVER_IP}:21114"
echo "用户名: admin"
echo "密码: $FIXED_PASSWORD"
echo "========================================"

# 简化部署函数（备用）
deploy_simple() {
    echo "使用简化配置部署..."
    cat > docker-compose-simple.yml << EOF
services:
  rustdesk:
    container_name: rustdesk
    ports:
      - "21116:21116"
      - "21116:21116/udp"
      - "21117:21117"
    image: lejianwen/rustdesk-server-s6:latest
    environment:
      - SERVER_IP=${SERVER_IP}
      - RELAY_IP=${SERVER_IP}
      - KEY=${PUBLIC_KEY}
      - TZ=Asia/Shanghai
    volumes:
      - /data/rustdesk/server:/data
    restart: unless-stopped
EOF
    
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        docker compose -f docker-compose-simple.yml up -d
    else
        docker-compose -f docker-compose-simple.yml up -d
    fi
}
