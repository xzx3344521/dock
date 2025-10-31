#!/bin/bash

echo "强制修复密钥问题..."

cd rustdesk-unified-keys

# 完全重置
docker-compose down 2>/dev/null || true
rm -rf server/*

# 重新生成密钥到正确位置
mkdir -p server keys

# 在server目录生成固定密钥（容器内的/root目录）
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

# 复制到keys目录备份
cp server/id_ed25519 keys/
cp server/id_ed25519.pub keys/

# 设置正确的权限
chmod 600 server/id_ed25519
chmod 644 server/id_ed25519.pub

# 检测IP
RELAY_SERVER=$(curl -s --connect-timeout 5 http://ipinfo.io/ip || curl -s --connect-timeout 5 http://ifconfig.me || hostname -I | awk '{print $1}')
echo "RELAY_SERVER=$RELAY_SERVER" > .env

# 使用完整的docker-compose配置
cat > docker-compose.yml << EOF
services:
  rustdesk:
    container_name: rustdesk-server
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
      - RELAY=${RELAY_SERVER}
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=N
      - TZ=Asia/Shanghai
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${RELAY_SERVER}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${RELAY_SERVER}:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://${RELAY_SERVER}:21114
      - RUSTDESK_API_RUSTDESK_KEY=2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=
      - RUSTDESK_API_RUSTDESK_KEY_FILE=/root/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=
      - RUSTDESK_API_LANG=zh-CN
      - RUSTDESK_API_APP_WEB_CLIENT=1
      - RUSTDESK_API_APP_REGISTER=false
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1
      - RUSTDESK_API_APP_BAN_THRESHOLD=0
    volumes:
      - ./server:/root
      - ./api-data:/app/data
    restart: unless-stopped

networks:
  rustdesk-net:
    driver: bridge
EOF

echo "验证密钥文件:"
ls -la server/
echo "公钥内容:"
cat server/id_ed25519.pub

echo "启动服务..."
docker-compose up -d

sleep 15
echo "服务状态:"
docker-compose ps

echo "查看密钥相关日志:"
docker-compose logs --tail=50 | grep -i "key\|Key"

echo "重置管理员密码: 3459635287"
docker exec -it rustdesk-server ./apimain reset-admin-pwd 3459635287

echo "=== 最终验证 ==="
SERVER_KEY=$(docker-compose logs | grep "Key:" | tail -1 | awk '{print $NF}')
FIXED_KEY="2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="

echo "服务器使用密钥: $SERVER_KEY"
echo "期望固定密钥: $FIXED_KEY"

if [ "$SERVER_KEY" = "$FIXED_KEY" ]; then
    echo "✅ 密钥匹配成功！"
    echo "客户端连接密钥: $FIXED_KEY"
else
    echo "❌ 密钥不匹配！"
    echo "调试信息:"
    docker-compose logs --tail=20 | grep -i key
fi

echo "=== 客户端配置 ==="
echo "ID服务器: ${RELAY_SERVER}:21116"
echo "中继服务器: ${RELAY_SERVER}:21117"
echo "API服务器: http://${RELAY_SERVER}:21114"
echo "密钥: 2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="
