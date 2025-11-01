
set -e

echo "🚀 RustDesk 服务器一键部署脚本 (网络优化版)"
echo "🚀 RustDesk 服务器一键部署脚本 (加速源可选版)"
echo "========================================"

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，正在安装 Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
fi
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

# 设置 Docker 镜像加速器
echo "🔧 配置 Docker 镜像加速..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
# 配置 Docker 加速器
setup_docker_accelerator() {
    case $ACCELERATOR in
        "china")
            echo "🔧 配置国内镜像加速器..."
            cat > /etc/docker/daemon.json << EOF
{
 "registry-mirrors": [
   "https://docker.mirrors.ustc.edu.cn",
@@ -25,14 +53,86 @@ cat > /etc/docker/daemon.json << EOF
 ]
}
EOF
systemctl daemon-reload
systemctl restart docker
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
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
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
@@ -80,7 +180,7 @@ echo "✅ 服务器 IP: $PUBLIC_IP"
# 生成管理员密码
ADMIN_PASSWORD=$(openssl rand -base64 12 2>/dev/null || date +%s | sha256sum | base64 | head -c 12)

# 创建 Docker Compose 配置（基于您的参考）
# 创建 Docker Compose 配置
cat > docker-compose.yml << EOF
networks:
 rustdesk-net:
@@ -132,14 +232,26 @@ echo "✅ 配置文件创建完成"
# 显示配置信息
echo ""
echo "📋 配置信息:"
echo "   加速源: $ACCELERATOR"
echo "   服务器IP: $PUBLIC_IP"
echo "   统一密钥: $UNIFIED_KEY_FINGERPRINT"
echo "   JWT密钥: $JWT_KEY"
echo "   管理员密码: $ADMIN_PASSWORD"
echo ""

# 拉取镜像
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
@@ -168,22 +280,6 @@ else
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
@@ -194,28 +290,19 @@ echo "   API 管理界面: http://$PUBLIC_IP:21114"
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
@@ -227,10 +314,3 @@ for port in 21114 21115 21116 21117; do
echo "❌ 端口 $port 无法连接"
fi
done

# 显示网络信息
echo ""
echo "🌐 网络配置:"
echo "   使用自定义网络: rustdesk-net"
echo "   网络模式: bridge (内部通信)"
docker network ls | grep rustdesk-net
