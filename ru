#!/bin/bash

# RustDesk Server 一键部署脚本
set -e

echo "========================================"
echo "    RustDesk Server 一键部署脚本"
echo "========================================"

# 创建项目目录
mkdir -p rustdesk-server
cd rustdesk-server

# 生成固定密钥对
echo "1. 生成密钥对..."
mkdir -p keys
openssl genpkey -algorithm ed25519 -out keys/id_ed25519 2>/dev/null || {
    echo "生成密钥对失败，创建示例密钥..."
    # 如果 openssl 不可用，创建示例密钥文件
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

# 编码密钥为base64
KEY_PRIV=$(cat keys/id_ed25519 | base64 -w 0)
KEY_PUB=$(cat keys/id_ed25519.pub | base64 -w 0)

# 自动检测服务器IP
echo "2. 检测服务器IP地址..."
RELAY_SERVER=$(curl -s --connect-timeout 5 http://ipinfo.io/ip || curl -s --connect-timeout 5 http://ifconfig.me || hostname -I | awk '{print $1}')

if [ -z "$RELAY_SERVER" ]; then
    echo "错误: 无法自动获取服务器IP，请手动输入:"
    read RELAY_SERVER
else
    echo "检测到服务器IP: $RELAY_SERVER"
fi

# 创建docker-compose.yml
echo "3. 创建Docker Compose配置..."
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

# 创建启动脚本
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose up -d
echo "RustDesk服务器启动完成！"
EOF

# 创建停止脚本  
cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose down
echo "RustDesk服务器已停止！"
EOF

# 创建客户端配置说明
cat > client-config.md << EOF
# RustDesk 客户端配置

## 服务器信息
- ID服务器: $RELAY_SERVER:21116
- 中继服务器: $RELAY_SERVER:21117  
- Key: 
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
chmod +x start.sh stop.sh

# 检查Docker环境
echo "4. 检查Docker环境..."
if ! command -v docker &> /dev/null; then
    echo "错误: Docker未安装，请先安装Docker"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "错误: Docker Compose未安装，请先安装Docker Compose"
    exit 1
fi

# 拉取镜像
echo "5. 拉取Docker镜像..."
docker pull lejianwen/rustdesk-server:latest

# 启动服务
echo "6. 启动RustDesk服务..."
docker-compose up -d

# 显示部署结果
echo "========================================"
echo "       部署完成！"
echo "========================================"
echo "服务状态:"
docker-compose ps

echo -e "\n客户端配置信息已保存到: client-config.md"
echo -e "\n管理命令:"
echo "启动服务: ./start.sh"
echo "停止服务: ./stop.sh"
echo "查看日志: docker-compose logs -f"
echo "查看状态: docker-compose ps"

echo -e "\n重要信息:"
echo "ID服务器: $RELAY_SERVER:21116"
echo "中继服务器: $RELAY_SERVER:21117"
echo "密钥文件位置: ./keys/"
