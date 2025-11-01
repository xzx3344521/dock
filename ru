#!/bin/bash

set -e  # 出现任何错误立即退出

echo "🚀 RustDesk 服务器一键部署脚本 (跨VPS统一密钥版)"
echo "=========================================================="

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，请先安装 Docker"
    exit 1
fi

# 检查 Docker Compose 是否可用
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose 不可用，请先安装 Docker Compose"
    exit 1
fi

# 使用 docker compose（新版本）或 docker-compose（旧版本）
DOCKER_COMPOSE_CMD="docker-compose"
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
fi

# 创建工作目录
WORK_DIR="rustdesk-server"
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
echo "📁 工作目录: $(pwd)"

# 清理现有服务
echo "🔄 清理现有服务..."
$DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || true

# 创建必要的目录结构
mkdir -p data/keys data/db

# 设置统一的固定密钥（跨VPS保持一致）
UNIFIED_PRIVATE_KEY="MC4CAQAwBQYDK2VwBCIEIAE8qD6H5JkG9T5s8s7XaYz1UvP6wQ3rN2tLbKj1mG"
UNIFIED_PUBLIC_KEY="MCowBQYDK2VwAyEA2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="
UNIFIED_KEY_FINGERPRINT="2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="

# 生成统一的密钥文件
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

# 设置正确的权限
chmod 600 data/keys/id_ed25519
chmod 644 data/keys/id_ed25519.pub

# 检测公网 IP
echo "🌐 检测服务器公网 IP..."
PUBLIC_IP=""
IP_SERVICES=(
    "http://ipinfo.io/ip"
    "http://ifconfig.me"
    "http://icanhazip.com"
    "http://ident.me"
)

for service in "${IP_SERVICES[@]}"; do
    if PUBLIC_IP=$(curl -s --connect-timeout 3 "$service"); then
        if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "✅ 从 $service 获取到 IP: $PUBLIC_IP"
            break
        fi
    fi
done

# 如果通过服务获取失败，使用本地IP
if [[ -z "$PUBLIC_IP" || ! "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
    echo "⚠️  使用本地 IP: $PUBLIC_IP"
fi

# 生成随机管理员密码
ADMIN_PASSWORD=$(openssl rand -base64 12 2>/dev/null || date +%s | sha256sum | base64 | head -c 12)
echo "🔐 生成管理员密码: $ADMIN_PASSWORD"

# 创建环境配置文件
cat > .env << EOF
# RustDesk 服务器配置
RELAY_SERVER=$PUBLIC_IP
PUBLIC_IP=$PUBLIC_IP
UNIFIED_KEY=$UNIFIED_KEY_FINGERPRINT
ADMIN_PASSWORD=$ADMIN_PASSWORD
TIMEZONE=Asia/Shanghai

# 安全配置
ENCRYPTED_ONLY=1
MUST_LOGIN=y

# API 配置
API_PORT=21114
WEB_CLIENT_PORT=21115
ID_SERVER_PORT=21116
RELAY_PORT=21117
WS_PORT=21118
EOF

# 创建 Docker Compose 配置
cat > docker-compose.yml << EOF
version: '3.8'

services:
  rustdesk-server:
    container_name: rustdesk-server
    image: lejianwen/rustdesk-server-s6:latest
    ports:
      - "\${API_PORT}:21114"           # API 管理界面
      - "\${WEB_CLIENT_PORT}:21115"    # 网页客户端
      - "\${ID_SERVER_PORT}:21116"     # ID 服务器 (TCP)
      - "\${ID_SERVER_PORT}:21116/udp" # ID 服务器 (UDP)
      - "\${RELAY_PORT}:21117"         # 中继服务器
      - "\${WS_PORT}:21118"            # WebSocket
      - "21119:21119"                  # 备用端口
    environment:
      # 网络配置
      - RELAY=\${RELAY_SERVER}
      - PUBLIC_IP=\${PUBLIC_IP}
      
      # 安全配置
      - ENCRYPTED_ONLY=\${ENCRYPTED_ONLY}
      - MUST_LOGIN=\${MUST_LOGIN}
      - FIXED_KEY=\${UNIFIED_KEY}
      
      # API 配置
      - RUSTDESK_API_RUSTDESK_ID_SERVER=\${PUBLIC_IP}:\${ID_SERVER_PORT}
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=\${PUBLIC_IP}:\${RELAY_PORT}
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://\${PUBLIC_IP}:\${API_PORT}
      - RUSTDESK_API_RUSTDESK_KEY=\${UNIFIED_KEY}
      - RUSTDESK_API_RUSTDESK_KEY_FILE=/root/keys/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=\${UNIFIED_KEY}
      
      # 网页客户端配置
      - RUSTDESK_API_APP_WEB_CLIENT=1
      - RUSTDESK_API_APP_REGISTER=false
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1
      - RUSTDESK_API_APP_BAN_THRESHOLD=0
      - RUSTDESK_API_LANG=zh-CN
      
      # 系统配置
      - TZ=\${TIMEZONE}
    volumes:
      - ./data/keys:/root/keys        # 统一密钥目录
      - ./data/db:/root/db            # 数据库目录
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "netstat", "-ltn"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  default:
    name: rustdesk-network
EOF

echo "✅ 配置文件创建完成"

# 启动服务
echo "🔄 启动 RustDesk 服务..."
$DOCKER_COMPOSE_CMD up -d

# 等待服务启动
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
fi

# 显示服务状态
echo "📊 服务状态:"
$DOCKER_COMPOSE_CMD ps

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
    $DOCKER_COMPOSE_CMD logs --tail=10
fi

# 显示最终配置信息
echo ""
echo "🎉 RustDesk 服务器部署完成！"
echo "=========================================================="
echo "🌐 访问地址:"
echo "   网页远程登录: http://$PUBLIC_IP:21115"
echo "   API 管理界面: http://$PUBLIC_IP:21114"
echo ""
echo "🔑 统一密钥配置:"
echo "   密钥指纹: $UNIFIED_KEY_FINGERPRINT"
echo "   私钥路径: $(pwd)/data/keys/id_ed25519"
echo "   公钥路径: $(pwd)/data/keys/id_ed25519.pub"
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
echo "=========================================================="

# 测试端口连通性
echo "🔍 测试服务端口..."
for port in 21114 21115 21116 21117; do
    if nc -z localhost $port 2>/dev/null; then
        echo "✅ 端口 $port 监听正常"
    else
        echo "❌ 端口 $port 无法连接"
    fi
done
