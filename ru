
set -e

echo "🚀 RustDesk 服务器一键部署脚本 (优化版)"
echo "🚀 RustDesk 服务器一键部署脚本 (官方镜像版)"
echo "========================================"

# 检查 Docker
@@ -79,61 +79,75 @@ echo "✅ 服务器 IP: $PUBLIC_IP"
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
# 创建 Docker Compose 配置（使用官方镜像）
cat > docker-compose.yml << EOF
services:
  rustdesk-server:
    container_name: rustdesk-server
    image: lejianwen/rustdesk-server-s6:latest
  hbbs:
    container_name: rustdesk-hbbs
    image: rustdesk/rustdesk-server:latest
    command: hbbs -r ${PUBLIC_IP}:21117
   ports:
      - "21114:21114"   # API 管理界面
     - "21115:21115"   # 网页客户端
     - "21116:21116"   # ID 服务器 (TCP)
     - "21116:21116/udp"
      - "21117:21117"   # 中继服务器
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
      - RUSTDESK_API_RUSTDESK_KEY=${UNIFIED_KEY_FINGERPRINT}
      - RUSTDESK_API_JWT_KEY=${UNIFIED_KEY_FINGERPRINT}
     - RUSTDESK_API_APP_WEB_CLIENT=1
     - RUSTDESK_API_APP_REGISTER=false
     - RUSTDESK_API_LANG=zh-CN
      - TZ=${TIMEZONE}
    volumes:
      - ./data/keys:/root/keys
      - ./data/db:/root/db
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
   restart: unless-stopped
    healthcheck:
      test: ["CMD", "netstat", "-ltn"]
      interval: 30s
      timeout: 10s
      retries: 3
    depends_on:
      - hbbs
      - hbbr
EOF

echo "✅ 配置文件创建完成"

# 拉取镜像（显示进度）
echo "📥 拉取 Docker 镜像..."
# 拉取镜像
echo "📥 拉取官方 RustDesk 镜像..."
$DOCKER_COMPOSE_CMD pull

# 启动服务
@@ -142,21 +156,52 @@ $DOCKER_COMPOSE_CMD up -d

# 等待启动
echo "⏳ 等待服务启动..."
sleep 30
for i in {1..30}; do
    if $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then
        echo "✅ 服务启动成功"
        break
    fi
    sleep 2
    echo -n "."
done

# 设置管理员密码
echo "🔐 设置管理员密码..."
docker exec rustdesk-server ./apimain reset-admin-pwd "$ADMIN_PASSWORD" 2>/dev/null || echo "⚠️ 密码设置可能需要重试"
sleep 10

# 显示部署结果
echo ""
echo "🎉 RustDesk 服务器部署完成！"
echo "========================================"
echo "🌐 网页远程登录: http://$PUBLIC_IP:21115"
echo "🔑 统一密钥: $UNIFIED_KEY_FINGERPRINT"
echo "🔐 管理员密码: $ADMIN_PASSWORD"
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
echo "   ID 服务器: $PUBLIC_IP:21116"
echo "   中继服务器: $PUBLIC_IP:21117"
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
