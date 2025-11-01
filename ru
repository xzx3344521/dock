#!/bin/bash

set -e  # 出现任何错误立即退出

echo "🚀 RustDesk 服务器一键部署脚本"
echo "========================================"

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
WORK_DIR="rustdesk-unified-keys"
cd "$WORK_DIR" 2>/dev/null || mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

echo "📁 工作目录: $(pwd)"

# 完全重置现有服务
echo "🔄 清理现有服务..."
$DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || true
rm -rf server/* keys/* api-data/* 2>/dev/null || true

# 创建必要的目录结构
mkdir -p server keys api-data

# 生成固定密钥到 server 目录（容器内的 /root 目录）
echo "🔑 生成加密密钥..."
cat > server/id_ed25519 << 'EOF'
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIAE8qD6H5JkG9T5s8s7XaYz1UvP6wQ3rN2tLbKj1mG
-----END PRIVATE KEY-----
EOF

cat > server/id_ed25519.pub << 'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=
-----END PUBLIC KEY-----
EOF

# 备份密钥到 keys 目录
cp server/id_ed25519 keys/
cp server/id_ed25519.pub keys/

# 设置正确的权限
chmod 600 server/id_ed25519
chmod 644 server/id_ed25519.pub

# 检测公网 IP
echo "🌐 检测服务器公网 IP..."
RELAY_SERVER=""
IP_SERVICES=(
    "http://ipinfo.io/ip"
    "http://ifconfig.me"
    "http://icanhazip.com"
    "http://ident.me"
)

for service in "${IP_SERVICES[@]}"; do
    if RELAY_SERVER=$(curl -s --connect-timeout 3 "$service"); then
        if [[ "$RELAY_SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "✅ 从 $service 获取到 IP: $RELAY_SERVER"
            break
        fi
    fi
done

# 如果通过服务获取失败，使用本地IP
if [[ -z "$RELAY_SERVER" || ! "$RELAY_SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    RELAY_SERVER=$(hostname -I | awk '{print $1}')
    echo "⚠️  使用本地 IP: $RELAY_SERVER"
fi

# 保存环境变量
cat > .env << EOF
# RustDesk 服务器配置
RELAY_SERVER=$RELAY_SERVER
FIXED_KEY=2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=
TIMEZONE=Asia/Shanghai
EOF

# 创建完整的 docker-compose 配置
cat > docker-compose.yml << EOF
services:
  rustdesk:
    container_name: rustdesk-server
    ports:
      - "21114:21114"   # API 服务器
      - "21115:21115"   # 网页客户端
      - "21116:21116"   # ID 服务器
      - "21116:21116/udp"
      - "21117:21117"   # 中继服务器
      - "21118:21118"   # 备用端口
      - "21119:21119"   # 备用端口
    image: lejianwen/rustdesk-server-s6:latest
    environment:
      - RELAY=\${RELAY_SERVER}
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=y
      - TZ=\${TIMEZONE}
      - RUSTDESK_API_RUSTDESK_ID_SERVER=\${RELAY_SERVER}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=\${RELAY_SERVER}:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://\${RELAY_SERVER}:21114
      - RUSTDESK_API_RUSTDESK_KEY=\${FIXED_KEY}
      - RUSTDESK_API_RUSTDESK_KEY_FILE=/root/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=\${FIXED_KEY}
      - RUSTDESK_API_LANG=zh-CN
      - RUSTDESK_API_APP_WEB_CLIENT=1
      - RUSTDESK_API_APP_REGISTER=false
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1
      - RUSTDESK_API_APP_BAN_THRESHOLD=0
    volumes:
      - ./server:/root
      - ./api-data:/app/data
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

# 验证密钥文件
echo "🔍 验证密钥文件:"
ls -la server/
echo "📄 公钥内容:"
cat server/id_ed25519.pub

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

sleep 5

# 显示服务状态
echo "📊 服务状态:"
$DOCKER_COMPOSE_CMD ps

# 重置管理员密码
echo "🔐 重置管理员密码..."
if docker exec -it rustdesk-server ./apimain reset-admin-pwd 3459635287 2>/dev/null; then
    echo "✅ 管理员密码已重置: 3459635287"
else
    echo "⚠️  密码重置可能失败，请手动检查"
fi

# 验证部署
echo "🔍 验证部署结果..."
SERVER_KEY=$($DOCKER_COMPOSE_CMD logs 2>/dev/null | grep "Key:" | tail -1 | awk '{print $NF}' || echo "")
FIXED_KEY="2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="

echo "=== 部署验证结果 ==="
echo "服务器使用密钥: $SERVER_KEY"
echo "期望固定密钥: $FIXED_KEY"

if [ "$SERVER_KEY" = "$FIXED_KEY" ]; then
    echo "✅ 密钥匹配成功！"
else
    echo "❌ 密钥不匹配！"
    echo "调试信息:"
    $DOCKER_COMPOSE_CMD logs --tail=20 | grep -i key 2>/dev/null || echo "未找到相关日志"
fi

# 显示最终配置信息
echo ""
echo "🎉 RustDesk 服务器部署完成！"
echo "========================================"
echo "📋 客户端配置信息:"
echo "   ID 服务器: ${RELAY_SERVER}:21116"
echo "   中继服务器: ${RELAY_SERVER}:21117" 
echo "   API 服务器: http://${RELAY_SERVER}:21114"
echo "   密钥: 2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="
echo "   管理员密码: 3459635287"
echo ""
echo "🔧 管理命令:"
echo "   查看日志: cd $WORK_DIR && $DOCKER_COMPOSE_CMD logs -f"
echo "   重启服务: cd $WORK_DIR && $DOCKER_COMPOSE_CMD restart"
echo "   停止服务: cd $WORK_DIR && $DOCKER_COMPOSE_CMD down"
echo "========================================"
