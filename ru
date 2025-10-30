#!/bin/bash

# RustDesk Server 一键部署脚本（包含Docker自动安装）
set -e

echo "========================================"
echo "    RustDesk Server 一键部署脚本"
echo "========================================"

# 检查并安装 Docker
install_docker() {
    echo "1. 检查并安装 Docker..."
    
    if command -v docker &> /dev/null; then
        echo "✓ Docker 已安装"
    else
        echo "正在安装 Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
        # 启动 Docker 服务
        systemctl start docker
        systemctl enable docker
        
        # 将当前用户加入 docker 组
        usermod -aG docker $USER || true
        echo "✓ Docker 安装完成"
    fi
}

# 检查并安装 Docker Compose
install_docker_compose() {
    echo "2. 检查并安装 Docker Compose..."
    
    if command -v docker-compose &> /dev/null; then
        echo "✓ Docker Compose 已安装"
    else
        echo "正在安装 Docker Compose..."
        
        # 下载 Docker Compose
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        
        # 设置执行权限
        chmod +x /usr/local/bin/docker-compose
        
        # 创建软链接（兼容旧版本）
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        
        echo "✓ Docker Compose 安装完成"
    fi
}

# 安装必要的依赖
install_dependencies() {
    echo "安装必要依赖..."
    
    if command -v apt &> /dev/null; then
        apt update
        apt install -y curl wget openssl
    elif command -v yum &> /dev/null; then
        yum install -y curl wget openssl
    elif command -v dnf &> /dev/null; then
        dnf install -y curl wget openssl
    else
        echo "⚠ 无法自动安装依赖，请手动安装 curl, wget, openssl"
    fi
}

# 主部署函数
deploy_rustdesk() {
    # 创建项目目录
    mkdir -p rustdesk-server
    cd rustdesk-server

    # 生成固定密钥对
    echo "3. 生成密钥对..."
    mkdir -p keys
    if command -v openssl &> /dev/null; then
        openssl genpkey -algorithm ed25519 -out keys/id_ed25519 2>/dev/null
        openssl pkey -in keys/id_ed25519 -pubout -out keys/id_ed25519.pub 2>/dev/null
    else
        echo "⚠ openssl 不可用，使用预生成密钥..."
        # 创建示例密钥文件
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
    fi

    # 编码密钥为base64
    KEY_PRIV=$(cat keys/id_ed25519 | base64 -w 0 2>/dev/null || echo "MC4CAQAwBQYDK2VwBCIEIAE8qD6H5JkG9T5s8s7XaYz1UvP6wQ3rN2tLbKj1mG")
    KEY_PUB=$(cat keys/id_ed25519.pub | base64 -w 0 2>/dev/null || echo "MCowBQYDK2VwAyEA2Q1Dp4q8q5V7s9kLx2mBwT3zN8rR6vY1zUj5tKfE=")

    # 自动检测服务器IP
    echo "4. 检测服务器IP地址..."
    RELAY_SERVER=$(curl -s --connect-timeout 5 http://ipinfo.io/ip || curl -s --connect-timeout 5 http://ifconfig.me || curl -s --connect-timeout 5 http://api.ipify.org || hostname -I | awk '{print $1}')

    if [ -z "$RELAY_SERVER" ]; then
        echo "错误: 无法自动获取服务器IP，请手动输入:"
        read RELAY_SERVER
    else
        echo "检测到服务器IP: $RELAY_SERVER"
    fi

    # 创建docker-compose.yml
    echo "5. 创建Docker Compose配置..."
    cat > docker-compose.yml << EOF
version: '3'

services:
  hbbs:
    container_name: hbbs
    ports:
      - "21115:21115"
      - "21116:21116" 
      - "21116:21116/udp"
      - "21118:21118"
    image: lejianwen/rustdesk-server:latest
    command: hbbs -r $RELAY_SERVER:21117
    volumes:
      - ./data:/root
    environment:
      - RELAY=$RELAY_SERVER
      - KEY_PUB=$KEY_PUB
      - KEY_PRIV=$KEY_PRIV
    restart: unless-stopped

  hbbr:
    container_name: hbbr  
    ports:
      - "21117:21117"
      - "21119:21119"
    image: lejianwen/rustdesk-server:latest
    volumes:
      - ./data:/root
    environment:
      - KEY_PUB=$KEY_PUB
      - KEY_PRIV=$KEY_PRIV
    restart: unless-stopped
EOF

    # 创建环境变量文件
    cat > .env << EOF
RELAY_SERVER=$RELAY_SERVER
KEY_PUB=$KEY_PUB
KEY_PRIV=$KEY_PRIV
EOF

    # 创建管理脚本
    create_management_scripts
}

# 创建管理脚本
create_management_scripts() {
    # 创建启动脚本
    cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose up -d
echo "RustDesk服务器启动完成！"
echo "ID服务器: $(grep RELAY_SERVER .env | cut -d= -f2):21116"
echo "中继服务器: $(grep RELAY_SERVER .env | cut -d= -f2):21117"
EOF

    # 创建停止脚本  
    cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose down
echo "RustDesk服务器已停止！"
EOF

    # 创建重启脚本
    cat > restart.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose restart
echo "RustDesk服务器已重启！"
EOF

    # 创建客户端配置说明
    cat > client-config.md << EOF
# RustDesk 客户端配置

## 服务器信息
- ID服务器: $RELAY_SERVER:21116
- 中继服务器: $RELAY_SERVER:21117  
- 公钥: 
\`\`\`
$(cat keys/id_ed25519.pub)
\`\`\`

## 配置步骤
1. 打开RustDesk客户端
2. 点击右下角设置按钮
3. 选择"网络"标签
4. 填写以下信息：
   - ID服务器: $RELAY_SERVER:21116
   - 中继服务器: $RELAY_SERVER:21117
   - Key: 粘贴上面的公钥内容
5. 点击"应用"保存设置

## 端口说明
- 21115: HTTP API端口
- 21116: ID服务器端口 (TCP)
- 21117: 中继服务器端口 (TCP)
- 21118: 网页客户端端口
- 21119: 中继服务器端口 (备用)
EOF

    # 设置脚本权限
    chmod +x start.sh stop.sh restart.sh
}

# 启动服务
start_services() {
    echo "6. 拉取Docker镜像..."
    docker pull lejianwen/rustdesk-server:latest

    echo "7. 启动RustDesk服务..."
    docker-compose up -d

    # 等待服务启动
    sleep 5
}

# 显示部署结果
show_result() {
    echo "========================================"
    echo "       部署完成！"
    echo "========================================"
    
    echo -e "\n服务状态:"
    docker-compose ps
    
    echo -e "\n管理命令:"
    echo "启动服务: ./start.sh"
    echo "停止服务: ./stop.sh"  
    echo "重启服务: ./restart.sh"
    echo "查看日志: docker-compose logs -f"
    echo "查看状态: docker-compose ps"
    
    echo -e "\n重要信息:"
    echo "ID服务器: $RELAY_SERVER:21116"
    echo "中继服务器: $RELAY_SERVER:21117"
    echo "密钥文件位置: ./keys/"
    echo -e "\n客户端配置信息已保存到: client-config.md"
    
    echo -e "\n⚠ 注意: 可能需要重新登录终端才能使用 docker 命令"
    echo "或者运行: newgrp docker"
}

# 主执行流程
main() {
    install_dependencies
    install_docker
    install_docker_compose
    deploy_rustdesk
    start_services
    show_result
}

# 执行主函数
main
