#!/bin/bash

set -e

echo "🚀 RustDesk 服务器一键部署脚本 (加速源可选版)"
echo "========================================"

# 加速源选择函数
select_accelerator() {
    echo "🌐 请选择加速源:"
    echo "1) 使用默认 Docker 官方源 (可能较慢)"
    echo "2) 使用国内镜像加速器"
    echo "3) 使用自定义加速源 github.vps7k7k.xyz"
    echo "4) 不使用加速器"
    
    read -p "请输入选择 [1-4]: " choice
    
    case $choice in
        1)
            echo "✅ 使用 Docker 官方源"
            ACCELERATOR="official"
            ;;
        2)
            echo "✅ 使用国内镜像加速器"
            ACCELERATOR="china"
            ;;
        3)
            echo "✅ 使用自定义加速源 github.vps7k7k.xyz"
            ACCELERATOR="custom"
            ;;
        4)
            echo "✅ 不使用加速器"
            ACCELERATOR="none"
            ;;
        *)
            echo "⚠️  无效选择，使用国内镜像加速器"
            ACCELERATOR="china"
            ;;
    esac
}

# 配置 Docker 加速器
setup_docker_accelerator() {
    case $ACCELERATOR in
        "china")
            echo "🔧 配置国内镜像加速器..."
            cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://registry.docker-cn.com"
  ]
}
EOF
            ;;
        "custom")
            echo "🔧 配置自定义加速源 github.vps7k7k.xyz..."
            cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://github.vps7k7k.xyz"
  ]
}
EOF
            ;;
        "official"|"none")
            echo "ℹ️  使用默认 Docker 官方源"
            rm -f /etc/docker/daemon.json
            ;;
    esac
    
    if [ "$ACCELERATOR" != "none" ]; then
        systemctl daemon-reload
        systemctl restart docker
        echo "✅ Docker 加速器配置完成"
    fi
}

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，正在安装 Docker..."
    
    # 选择加速源
    select_accelerator
    
    # 根据选择配置安装源
    case $ACCELERATOR in
        "china")
            echo "📥 使用国内源安装 Docker..."
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
            ;;
        "custom")
            echo "📥 使用自定义加速源安装 Docker..."
            curl -fsSL https://get.docker.com | bash
            ;;
        *)
            echo "📥 使用官方源安装 Docker..."
            curl -fsSL https://get.docker.com | bash
            ;;
    esac
    
    systemctl start docker
    systemctl enable docker
else
    # 如果 Docker 已安装，选择加速源
    select_accelerator
fi

# 配置 Docker 加速器
mkdir -p /etc/docker
setup_docker_accelerator

# 检查 Docker Compose
DOCKER_COMPOSE_CMD="docker compose"
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "📥 安装 Docker Compose..."
    
    # 根据加速源选择下载地址
    case $ACCELERATOR in
        "china")
            # 使用国内镜像下载
            COMPOSE_URL="https://ghproxy.com/https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)"
            ;;
        "custom")
            # 使用自定义加速源
            COMPOSE_URL="https://github.vps7k7k.xyz/https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)"
            ;;
        *)
            # 使用官方源
            COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)"
            ;;
    esac
    
    curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose
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

# 创建 Docker Compose 配置
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
echo "   加速源: $ACCELERATOR"
echo "   服务器IP: $PUBLIC_IP"
echo "   统一密钥: $UNIFIED_KEY_FINGERPRINT"
echo "   管理员密码: $ADMIN_PASSWORD"
echo ""

# 拉取镜像（根据加速源显示不同信息）
echo "📥 拉取 Docker 镜像..."
case $ACCELERATOR in
    "china")
        echo "ℹ️  使用国内镜像加速器拉取镜像..."
        ;;
    "custom")
        echo "ℹ️  使用自定义加速源 github.vps7k7k.xyz 拉取镜像..."
        ;;
    *)
        echo "ℹ️  使用默认源拉取镜像..."
        ;;
esac

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
echo ""
echo "🔐 登录信息:"
echo "   管理员密码: $ADMIN_PASSWORD"
echo ""
echo "📡 客户端配置:"
echo "   ID 服务器: $PUBLIC_IP:21116"
echo "   中继服务器: $PUBLIC_IP:21117"
echo "   密钥: $UNIFIED_KEY_FINGERPRINT"
echo ""
echo "🔧 管理命令:"
echo "   查看日志: cd $WORK_DIR && $DOCKER_COMPOSE_CMD logs -f"
echo "   重启服务: cd $WORK_DIR && $DOCKER_COMPOSE_CMD restart"
echo "   停止服务: cd $WORK_DIR && $DOCKER_COMPOSE_CMD down"
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
