#!/bin/bash

set -e

echo "🚀 RustDesk 服务器一键部署脚本 (优化版)"
echo "========================================"

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，正在安装 Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
fi

# 设置 Docker 镜像加速器
echo "🔧 配置 Docker 镜像加速..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://registry.docker-cn.com"
  ]
}
EOF
systemctl daemon-reload
systemctl restart docker

# 检查 Docker Compose
DOCKER_COMPOSE_CMD="docker compose"
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "📥 安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# 创建工作目录
WORK_DIR="rustdesk-server"
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
echo "📁 工作目录: $(pwd)"

# 清理现有服务
echo "🔄 清理现有服务..."
$DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || true

# 创建目录结构
mkdir -p data/keys data/db

# 统一密钥配置
UNIFIED_PRIVATE_KEY="MC4CAQAwBQYDK2VwBCIEIAE8qD6H5JkG9T5s8s7XaYz1UvP6wQ3rN2tLbKj1mG"
UNIFIED_PUBLIC_KEY="MCowBQYDK2VwAyEA2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="
UNIFIED_KEY_FINGERPRINT="2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="

# 生成密钥文件
echo "🔑 生成统一密钥..."
cat > data/keys/id_ed25519 << EOF
-----BEGIN PRIVATE KEY-----
$UNIFIED_PRIVATE_KEY
-----END PRIVATE KEY-----
EOF

cat > data/keys/id_ed25519.pub << EOF
-----BEGIN PUBLIC KEY-----
$UNIFIED_PUBLIC_KEY
-----END PUBLIC KEY-----
EOF

chmod 600 data/keys/id_ed25519
chmod 644 data/keys/id_ed25519.pub

# 检测公网 IP
echo "🌐 检测服务器公网 IP..."
PUBLIC_IP=$(curl -s --connect-timeout 5 http://ipinfo.io/ip || hostname -I | awk '{print $1}')
echo "✅ 服务器 IP: $PUBLIC_IP"

# 生成管理员密码
ADMIN_PASSWORD=$(openssl rand -base64 12 2>/dev/null || date +%s | sha256sum | base64 | head -c 12)

# 创建环境配置
cat > .env << EOF
PUBLIC_IP=$PUBLIC_IP
UNIFIED_KEY=$UNIFIED_KEY_FINGERPRINT
ADMIN_PASSWORD=$ADMIN_PASSWORD
TIMEZONE=Asia/Shanghai
ENCRYPTED_ONLY=1
MUST_LOGIN=y
EOF

# 创建 Docker Compose 配置（修复版本警告）
cat > docker-compose.yml << 'EOF'
services:
  rustdesk-server:
    container_name: rustdesk-server
    image: lejianwen/rustdesk-server-s6:latest
    ports:
      - "21114:21114"   # API 管理界面
      - "21115:21115"   # 网页客户端
      - "21116:21116"   # ID 服务器 (TCP)
      - "21116:21116/udp"
      - "21117:21117"   # 中继服务器
      - "21118:21118"   # WebSocket
      - "21119:21119"   # 备用端口
    environment:
      - RELAY=${PUBLIC_IP}
      - PUBLIC_IP=${PUBLIC_IP}
      - ENCRYPTED_ONLY=${ENCRYPTED_ONLY}
      - MUST_LOGIN=${MUST_LOGIN}
      - FIXED_KEY=${UNIFIED_KEY}
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${PUBLIC_IP}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${PUBLIC_IP}:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://${PUBLIC_IP}:21114
      - RUSTDESK_API_RUSTDESK_KEY=${UNIFIED_KEY}
      - RUSTDESK_API_RUSTDESK_KEY_FILE=/root/keys/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=${UNIFIED_KEY}
      - RUSTDESK_API_APP_WEB_CLIENT=1
      - RUSTDESK_API_APP_REGISTER=false
      - RUSTDESK_API_LANG=zh-CN
      - TZ=${TIMEZONE}
    volumes:
      - ./data/keys:/root/keys
      - ./data/db:/root/db
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "netstat", "-ltn"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

echo "✅ 配置文件创建完成"

# 拉取镜像（显示进度）
echo "📥 拉取 Docker 镜像..."
$DOCKER_COMPOSE_CMD pull

# 启动服务
echo "🔄 启动服务..."
$DOCKER_COMPOSE_CMD up -d

# 等待启动
echo "⏳ 等待服务启动..."
sleep 30

# 设置管理员密码
echo "🔐 设置管理员密码..."
docker exec rustdesk-server ./apimain reset-admin-pwd "$ADMIN_PASSWORD" 2>/dev/null || echo "⚠️ 密码设置可能需要重试"

# 显示部署结果
echo ""
echo "🎉 RustDesk 服务器部署完成！"
echo "========================================"
echo "🌐 网页远程登录: http://$PUBLIC_IP:21115"
echo "🔑 统一密钥: $UNIFIED_KEY_FINGERPRINT"
echo "🔐 管理员密码: $ADMIN_PASSWORD"
echo ""
echo "📡 客户端配置:"
echo "   ID 服务器: $PUBLIC_IP:21116"
echo "   中继服务器: $PUBLIC_IP:21117"
echo "========================================"
