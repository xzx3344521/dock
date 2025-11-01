#!/bin/bash

set -e

echo "🚀 RustDesk 服务器一键部署脚本 (官方镜像版)"
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

# 创建 Docker Compose 配置（使用官方镜像）
cat > docker-compose.yml << EOF
services:
  hbbs:
    container_name: rustdesk-hbbs
    image: rustdesk/rustdesk-server:latest
    command: hbbs -r ${PUBLIC_IP}:21117
    ports:
      - "21115:21115"   # 网页客户端
      - "21116:21116"   # ID 服务器 (TCP)
      - "21116:21116/udp"
      - "21118:21118"   # WebSocket
    volumes:
      - ./data/keys:/root
      - ./data/db:/root
    environment:
      - RELAY_SERVER=${PUBLIC_IP}
      - FIXED_KEY=${UNIFIED_KEY_FINGERPRINT}
      - MUST_LOGIN=y
      - ENCRYPTED_ONLY=1
    restart: unless-stopped

  hbbr:
    container_name: rustdesk-hbbr
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    ports:
      - "21117:21117"   # 中继服务器
      - "21119:21119"   # 备用端口
    volumes:
      - ./data/keys:/root
      - ./data/db:/root
    environment:
      - RELAY_SERVER=${PUBLIC_IP}
      - FIXED_KEY=${UNIFIED_KEY_FINGERPRINT}
      - MUST_LOGIN=y
      - ENCRYPTED_ONLY=1
    restart: unless-stopped

  api:
    container_name: rustdesk-api
    image: rustdesk/rustdesk-server:latest
    command: ./apimain
    ports:
      - "21114:21114"   # API 管理界面
    volumes:
      - ./data/keys:/root
      - ./data/db:/root
    environment:
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${PUBLIC_IP}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${PUBLIC_IP}:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://${PUBLIC_IP}:21114
      - RUSTDESK_API_RUSTDESK_KEY=${UNIFIED_KEY_FINGERPRINT}
      - RUSTDESK_API_JWT_KEY=${UNIFIED_KEY_FINGERPRINT}
      - RUSTDESK_API_APP_WEB_CLIENT=1
      - RUSTDESK_API_APP_REGISTER=false
      - RUSTDESK_API_LANG=zh-CN
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
    restart: unless-stopped
    depends_on:
      - hbbs
      - hbbr
EOF

echo "✅ 配置文件创建完成"

# 拉取镜像
echo "📥 拉取官方 RustDesk 镜像..."
$DOCKER_COMPOSE_CMD pull

# 启动服务
echo "🔄 启动服务..."
$DOCKER_COMPOSE_CMD up -d

# 等待启动
echo "⏳ 等待服务启动..."
for i in {1..30}; do
    if $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then
        echo "✅ 服务启动成功"
        break
    fi
    sleep 2
    echo -n "."
done

sleep 10

# 显示部署结果
echo ""
echo "🎉 RustDesk 服务器部署完成！"
echo "========================================"
echo "📊 服务状态:"
$DOCKER_COMPOSE_CMD ps

echo ""
echo "🌐 访问地址:"
echo "   网页远程登录: http://${PUBLIC_IP}:21115"
echo "   API 管理界面: http://${PUBLIC_IP}:21114"
echo ""
echo "🔑 统一密钥配置:"
echo "   密钥指纹: ${UNIFIED_KEY_FINGERPRINT}"
echo ""
echo "🔐 登录信息:"
echo "   管理员密码: ${ADMIN_PASSWORD}"
echo ""
echo "📡 客户端配置:"
echo "   ID 服务器: ${PUBLIC_IP}:21116"
echo "   中继服务器: ${PUBLIC_IP}:21117"
echo "   密钥: ${UNIFIED_KEY_FINGERPRINT}"
echo ""
echo "🔧 管理命令:"
echo "   查看日志: cd ${WORK_DIR} && ${DOCKER_COMPOSE_CMD} logs -f"
echo "   重启服务: cd ${WORK_DIR} && ${DOCKER_COMPOSE_CMD} restart"
echo "   停止服务: cd ${WORK_DIR} && ${DOCKER_COMPOSE_CMD} down"
echo "========================================"

# 测试端口连通性
echo "🔍 测试服务端口..."
for port in 21114 21115 21116 21117; do
    if nc -z localhost $port 2>/dev/null; then
        echo "✅ 端口 $port 监听正常"
    else
        echo "❌ 端口 $port 无法连接"
    fi
done
