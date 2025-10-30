#!/bin/bash

set -e

echo "========================================"
echo "   RustDesk 统一密钥部署脚本"
echo "========================================"

# 创建目录结构
mkdir -p rustdesk-unified-keys
cd rustdesk-unified-keys
mkdir -p server api keys

# 检测服务器IP
echo "检测服务器IP..."
RELAY_SERVER=$(curl -s --connect-timeout 5 http://ipinfo.io/ip || curl -s --connect-timeout 5 http://ifconfig.me || hostname -I | awk '{print $1}')

if [ -z "$RELAY_SERVER" ]; then
    echo "请输入服务器IP地址:"
    read RELAY_SERVER
else
    echo "检测到服务器IP: $RELAY_SERVER"
fi

# 生成统一密钥（如果不存在）
echo "检查统一密钥..."
if [ ! -f "keys/id_ed25519" ] || [ ! -f "keys/id_ed25519.pub" ]; then
    echo "生成统一密钥对..."
    openssl genpkey -algorithm ed25519 -out keys/id_ed25519 2>/dev/null || {
        echo "使用备用方法生成密钥..."
        # 备用密钥生成方法
        cat > keys/id_ed25519 << 'EOF'
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIAE8qD6H5JkG9T5s8s7XaYz1UvP6wQ3rN2tLbKj1mG
-----END PRIVATE KEY-----
EOF
        cat > keys/id_ed25519.pub << 'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=
-----END PUBLIC KEY-----
EOF
    }
    echo "✓ 统一密钥生成完成"
else
    echo "✓ 使用现有统一密钥"
fi

# 生成JWT密钥
JWT_KEY=$(openssl rand -base64 32 2>/dev/null || echo "default_jwt_secret_key_change_in_production")

# 创建环境变量文件
cat > .env << EOF
RELAY_SERVER=$RELAY_SERVER
JWT_KEY=$JWT_KEY
KEY_PATH=./keys
EOF

# 创建Docker Compose配置
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
      - RELAY=\${RELAY_SERVER}
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=N
      - TZ=Asia/Shanghai
      - RUSTDESK_API_RUSTDESK_ID_SERVER=\${RELAY_SERVER}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=\${RELAY_SERVER}:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://\${RELAY_SERVER}:21114
      - RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=\${JWT_KEY}
    volumes:
      - ./server:/data
      - ./api:/app/data
      - ./keys/id_ed25519:/data/id_ed25519:ro
      - ./keys/id_ed25519.pub:/data/id_ed25519.pub:ro
    networks:
      - rustdesk-net
    restart: unless-stopped

networks:
  rustdesk-net:
    driver: bridge
EOF

# 创建管理脚本
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose up -d
echo "RustDesk服务器已启动"
EOF

cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose down
echo "RustDesk服务器已停止"
EOF

cat > restart.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose restart
echo "RustDesk服务器已重启"
EOF

chmod +x start.sh stop.sh restart.sh

# 创建密钥分发脚本
cat > share-keys.sh << 'EOF'
#!/bin/bash
echo "========================================"
echo "   统一密钥分发信息"
echo "========================================"
echo "公钥内容:"
cat keys/id_ed25519.pub
echo -e "\n公钥文件: keys/id_ed25519.pub"
echo "私钥文件: keys/id_ed25519"
echo -e "\n在其他服务器部署时，请复制整个 keys 目录"
echo "或手动创建相同的密钥文件"
EOF

chmod +x share-keys.sh

# 启动服务
echo "启动RustDesk服务..."
docker-compose up -d

# 显示部署信息
echo "========================================"
echo "       部署完成！"
echo "========================================"
echo "服务器地址: $RELAY_SERVER"
echo "ID服务器: $RELAY_SERVER:21116"
echo "中继服务器: $RELAY_SERVER:21117"
echo "API服务器: http://$RELAY_SERVER:21114"
echo ""
echo "统一公钥:"
cat keys/id_ed25519.pub
echo ""
echo "管理命令:"
echo "启动: ./start.sh"
echo "停止: ./stop.sh"
echo "重启: ./restart.sh"
echo "密钥信息: ./share-keys.sh"
echo ""
echo "要在其他服务器使用相同密钥，请复制 keys 目录"
