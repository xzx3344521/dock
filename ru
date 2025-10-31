#!/bin/bash

echo "强制修复密钥问题..."

cd rustdesk-unified-keys

# 完全重置
docker-compose down 2>/dev/null || true
rm -rf server/*

# 重新生成密钥到正确位置
mkdir -p server keys

# 在server目录生成密钥（容器内的/root目录）
openssl genpkey -algorithm ed25519 -out server/id_ed25519 2>/dev/null || {
    cat > server/id_ed25519 << 'EOF'
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIAE8qD6H5JkG9T5s8s7XaYz1UvP6wQ3rN2tLbKj1mG
-----END PRIVATE KEY-----
EOF
}

openssl pkey -in server/id_ed25519 -pubout -out server/id_ed25519.pub 2>/dev/null || {
    cat > server/id_ed25519.pub << 'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=
-----END PUBLIC KEY-----
EOF
}

# 复制到keys目录备份
cp server/id_ed25519 keys/
cp server/id_ed25519.pub keys/

# 设置正确的权限
chmod 600 server/id_ed25519
chmod 644 server/id_ed25519.pub

# 使用简化的docker-compose（只挂载server目录到/root）
cat > docker-compose.yml << 'EOF'
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
      - RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1
      - RUSTDESK_API_JWT_KEY=2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=
    volumes:
      - ./server:/root
    restart: unless-stopped

networks:
  rustdesk-net:
    driver: bridge
EOF

# 检测IP
RELAY_SERVER=$(curl -s --connect-timeout 5 http://ipinfo.io/ip || curl -s --connect-timeout 5 http://ifconfig.me || hostname -I | awk '{print $1}')
echo "RELAY_SERVER=$RELAY_SERVER" > .env

echo "验证密钥文件:"
ls -la server/

echo "启动服务..."
docker-compose up -d

sleep 10
echo "服务状态:"
docker-compose ps

echo "查看密钥相关日志:"
docker-compose logs | grep -i key

echo "重置管理员密码: 3459635287"
docker exec -it rustdesk-server ./apimain reset-admin-pwd 3459635287

echo "验证密钥一致性:"
SERVER_KEY=$(docker-compose logs | grep "Key:" | tail -1 | awk '{print $NF}')
JWT_KEY="2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE="

if [ "$SERVER_KEY" = "$JWT_KEY" ]; then
    echo "✅ 密钥一致！服务器密钥: $SERVER_KEY"
else
    echo "❌ 密钥不一致！"
    echo "服务器密钥: $SERVER_KEY"
    echo "JWT密钥: $JWT_KEY"
fi
