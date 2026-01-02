#!/bin/bash

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
PLAIN="\033[0m"

echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      RustDesk Server (S6版) 一键部署脚本      ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"

# 1. 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# 2. 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}未检测到 Docker，请先安装 Docker 和 Docker Compose！${PLAIN}"
    echo -e "你可以尝试运行：curl -fsSL https://get.docker.com | bash"
    exit 1
fi

# 3. 设置安装目录
INSTALL_DIR="/data/rustdesk"
echo -e "${YELLOW}默认安装目录: ${INSTALL_DIR}${PLAIN}"

# 创建目录
mkdir -p "${INSTALL_DIR}/data"
mkdir -p "${INSTALL_DIR}/api"

# 4. 获取用户输入 (公网IP/域名)
read -p "请输入服务器的公网 IP 或解析好的域名 (必填): " HOST_IP
if [[ -z "$HOST_IP" ]]; then
    echo -e "${RED}错误：必须输入 IP 或域名！${PLAIN}"
    exit 1
fi

# 进入目录
cd "$INSTALL_DIR" || exit

# 5. 生成 docker-compose.yml
echo -e "${YELLOW}正在生成配置文件...${PLAIN}"

cat > docker-compose.yml <<EOF
version: '3'

networks:
  rustdesk-net:
    external: false

services:
  rustdesk:
    container_name: rustdesk-server
    ports:
      - 21114:21114
      - 21115:21115
      - 21116:21116
      - 21116:21116/udp
      - 21117:21117
      - 21118:21118
      - 21119:21119
    image: lejianwen/rustdesk-server-s6:latest
    environment:
      # 公网IP或域名
      - RELAY=${HOST_IP}
      # 强制必须登录才能连接
      - MUST_LOGIN=Y
      # 单个连接限速 2MB/s = 16Mb/s
      - SINGLE_BANDWIDTH=16
      # 总带宽限制
      - TOTAL_BANDWIDTH=100
      # 只允许加密连接
      - ENCRYPTED_ONLY=1
      # 时区设置
      - TZ=Asia/Shanghai
    volumes:
      # 密钥和数据持久化目录
      - ${INSTALL_DIR}/data:/data
      # API数据库目录
      - ${INSTALL_DIR}/api:/app/data
    networks:
      - rustdesk-net
    restart: unless-stopped
EOF

# 6. 启动容器
echo -e "${YELLOW}正在拉取镜像并启动容器...${PLAIN}"
docker compose pull
docker compose up -d

# 7. 检查状态并获取 Key
if [ $? -eq 0 ]; then
    echo -e "${GREEN}服务启动成功！${PLAIN}"
    echo -e "${YELLOW}正在等待密钥生成 (约5秒)...${PLAIN}"
    sleep 5
    
    # 尝试读取公钥
    PUB_KEY_FILE="${INSTALL_DIR}/data/id_ed25519.pub"
    
    if [ -f "$PUB_KEY_FILE" ]; then
        PUB_KEY=$(cat "$PUB_KEY_FILE")
        echo -e "${GREEN}=============================================${PLAIN}"
        echo -e "   RustDesk Server 部署完成信息"
        echo -e "${GREEN}=============================================${PLAIN}"
        echo -e "ID 服务器 (ID Server):  ${GREEN}${HOST_IP}${PLAIN}"
        echo -e "中继服务器 (Relay Server): ${GREEN}${HOST_IP}${PLAIN}"
        echo -e "API 服务器 (API Server):   ${GREEN}http://${HOST_IP}:21114${PLAIN}"
        echo -e "Key (公钥):"
        echo -e "${YELLOW}${PUB_KEY}${PLAIN}"
        echo -e "${GREEN}=============================================${PLAIN}"
        echo -e "请将以上信息填入 RustDesk 客户端的网络设置中。"
    else
        echo -e "${RED}无法自动读取公钥，请手动检查目录：${INSTALL_DIR}/data${PLAIN}"
        echo -e "或者查看日志：docker logs rustdesk-server"
    fi
else
    echo -e "${RED}服务启动失败，请检查 Docker 日志。${PLAIN}"
fi
