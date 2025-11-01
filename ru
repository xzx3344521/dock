#!/bin/bash

set -e

echo "🚀 RustDesk 服务器一键部署脚本 (网络优化版)"
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
WORK_DIR="/data/rustdesk"
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
echo "📁 工作目录: $(pwd)"

# 清理现有服务
echo "🔄 清理现有服务..."
$DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || true

# 创建目录结构
mkdir -p server api

# 统一密钥配置
UNIFIED_PRIVATE_KEY="MC4CAQAwBQYDK2VwBCIEIAE8qD6H5JkG9T5s8s7XaYz1UvP6wQ3rN2tLbKj1mG"
UNIFIED_PUBLIC_KEY="MCowBQYDK2VwAyEA2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="
UNIFIED_KEY_FINGERPRINT="2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="
JWT_KEY="jwt_secret_key_$(openssl rand -base64 12 2>/dev/null || date +%s | sha256sum | base64 | head -c 16)"

# 生成密钥文件
echo "🔑 生成统一密钥..."
cat > server/id_ed25519 << EOF
-----BEGIN PRIVATE KEY-----
$UNIFIED_PRIVATE_KEY
-----END PRIVATE KEY-----
EOF

cat > server/id_ed25519.pub << EOF
-----BEGIN PUBLIC KEY-----
$UNIFIED_PUBLIC_KEY
-----END PUBLIC KEY-----
EOF

chmod 600 server/id_ed25519
chmod 644 server/id_ed25519.pub

# 检测公网 IP
echo "🌐 检测服务器公网 IP..."
PUBLIC_IP=$(curl -s --connect-timeout 5 http://ipinfo.io/ip || hostname -I | awk '{print $1}')
echo "✅ 服务器 IP: $PUBLIC_IP"

# 生成管理员密码
ADMIN_PASSWORD=$(openssl rand -base64 12 2>/dev/null || date +%s | sha256sum | base64 | head -c 12)

# 创建 Docker Compose 配置（基于您的参考）
cat > docker-compose.yml << EOF
networks:
  rustdesk-net:
    external: false

services:
  rustdesk:
    container_name: rustdesk-server
    ports:
      - "21114:21114"   # API 服务器
      - "21115:21115"   # 网页客户端
      - "21116:21116"   # ID 服务器
      - "21116:21116/udp"
      - "21117:21117"   # 中继服务器
      - "21118:21118"   # WebSocket
      - "21119:21119"   # 备用端口
    image: lejianwen/rustdesk-server-s6:latest
    environment:
      - RELAY=$PUBLIC_IP:21117
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=Y
      - TZ=Asia/Shanghai
      - RUSTDESK_API_RUSTDESK_ID_SERVER=$PUBLIC_IP:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=$PUBLIC_IP:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://$PUBLIC_IP:21114
      - RUSTDESK_API_RUSTDESK_KEY=$UNIFIED_KEY_FINGERPRINT
      - RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=$JWT_KEY
      - RUSTDESK_API_LANG=zh-CN
      - RUSTDESK_API_APP_WEB_CLIENT=1
      - RUSTDESK_API_APP_REGISTER=false
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1
      - RUSTDESK_API_APP_BAN_THRESHOLD=0
    volumes:
      - ./server:/data
      - ./api:/app/data
    networks:
      - rustdesk-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "netstat", "-ltn"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

echo "✅ 配置文件创建完成"

# 显示配置信息
echo ""
echo "📋 配置信息:"
echo "   服务器IP: $PUBLIC_IP"
echo "   统一密钥: $UNIFIED_KEY_FINGERPRINT"
echo "   JWT密钥: $JWT_KEY"
echo "   管理员密码: $ADMIN_PASSWORD"
echo ""

# 拉取镜像
echo "📥 拉取 Docker 镜像..."
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

# 重置管理员密码
echo "🔐 设置管理员密码..."
if docker exec -it rustdesk-server ./apimain reset-admin-pwd "$ADMIN_PASSWORD" 2>/dev/null; then
    echo "✅ 管理员密码设置成功"
else
    echo "⚠️  密码设置可能失败，请手动检查"
    echo "   手动设置命令: docker exec -it rustdesk-server ./apimain reset-admin-pwd 新密码"
fi

# 验证密钥一致性
echo "🔍 验证密钥一致性..."
SERVER_KEY=$($DOCKER_COMPOSE_CMD logs 2>/dev/null | grep "Key:" | tail -1 | awk '{print $NF}' || echo "")

echo "=== 部署验证结果 ==="
echo "服务器使用密钥: $SERVER_KEY"
echo "统一固定密钥: $UNIFIED_KEY_FINGERPRINT"

if [ "$SERVER_KEY" = "$UNIFIED_KEY_FINGERPRINT" ]; then
    echo "✅ 密钥匹配成功！跨VPS密钥统一"
else
    echo "❌ 密钥不匹配！"
    echo "调试信息:"
    $DOCKER_COMPOSE_CMD logs --tail=10 | grep -i key 2>/dev/null || echo "未找到相关日志"
fi

# 显示最终配置信息
echo ""
echo "🎉 RustDesk 服务器部署完成！"
echo "========================================"
echo "🌐 访问地址:"
echo "   网页远程登录: http://$PUBLIC_IP:21115"
echo "   API 管理界面: http://$PUBLIC_IP:21114"
echo ""
echo "🔑 统一密钥配置:"
echo "   密钥指纹: $UNIFIED_KEY_FINGERPRINT"
echo "   私钥路径: $WORK_DIR/server/id_ed25519"
echo "   公钥路径: $WORK_DIR/server/id_ed25519.pub"
echo ""
echo "🔐 登录信息:"
echo "   管理员密码: $ADMIN_PASSWORD"
echo "   (首次登录后请立即修改密码)"
echo ""
echo "📡 客户端配置:"
echo "   ID 服务器: $PUBLIC_IP:21116"
echo "   中继服务器: $PUBLIC_IP:21117"
echo "   API 服务器: http://$PUBLIC_IP:21114"
echo "   密钥: $UNIFIED_KEY_FINGERPRINT"
echo ""
echo "🔧 管理命令:"
echo "   查看日志: cd $WORK_DIR && $DOCKER_COMPOSE_CMD logs -f"
echo "   重启服务: cd $WORK_DIR && $DOCKER_COMPOSE_CMD restart"
echo "   停止服务: cd $WORK_DIR && $DOCKER_COMPOSE_CMD down"
echo "   进入容器: docker exec -it rustdesk-server /bin/bash"
echo ""
echo "💾 数据目录:"
echo "   服务器配置: $WORK_DIR/server/"
echo "   数据库文件: $WORK_DIR/api/"
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

# 显示网络信息
echo ""
echo "🌐 网络配置:"
echo "   使用自定义网络: rustdesk-net"
echo "   网络模式: bridge (内部通信)"
docker network ls | grep rustdesk-net
