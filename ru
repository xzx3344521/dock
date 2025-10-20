#!/bin/bash

# 设置错误处理
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查端口是否被占用
check_port() {
    local port=$1
    local protocol=${2:-tcp}
    
    if command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":${port} "; then
            return 1
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":${port} "; then
            return 1
        fi
    fi
    
    # 检查 Docker 容器是否占用了端口
    if docker ps --format "table {{.Ports}}" | grep -q ":${port}->"; then
        return 1
    fi
    
    return 0
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查 Docker 服务状态
    if ! docker info &> /dev/null; then
        log_error "Docker 服务未运行，请启动 Docker 服务"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    fi
    
    log_success "Docker 环境检查通过"
}

# 创建目录结构
create_directories() {
    local dirs=("/data/rustdesk/server" "/data/rustdesk/api" "/data/rustdesk/db")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
            log_info "创建目录: $dir"
        else
            log_info "目录已存在: $dir"
        fi
    done
    
    # 设置目录权限
    sudo chmod 755 /data/rustdesk
    sudo chmod 755 /data/rustdesk/server
    sudo chmod 755 /data/rustdesk/api
    sudo chmod 755 /data/rustdesk/db
    
    # 设置所有权（如果当前用户不是root）
    if [ "$(id -u)" -ne 0 ]; then
        sudo chown -R "$(id -u):$(id -g)" /data/rustdesk
    fi
}

# 生成密钥对
generate_keypair() {
    local server_dir="/data/rustdesk/server"
    
    log_info "生成 RustDesk 密钥对..."
    
    # 检查是否已存在密钥对
    if [[ -f "$server_dir/id_ed25519" && -f "$server_dir/id_ed25519.pub" ]]; then
        log_warning "密钥对已存在，跳过生成"
        KEY_PUB=$(cat "$server_dir/id_ed25519.pub")
        KEY_PRIV=$(cat "$server_dir/id_ed25519")
        return
    fi
    
    # 使用 Docker 容器生成密钥对
    if docker run --rm --entrypoint /usr/bin/rustdesk-utils lejianwen/rustdesk-server-s6:latest genkeypair > /tmp/rustdesk_keys 2>/dev/null; then
        # 解析生成的密钥
        KEY_PUB=$(grep "Public Key:" /tmp/rustdesk_keys | awk '{print $3}')
        KEY_PRIV=$(grep "Secret Key:" /tmp/rustdesk_keys | awk '{print $3}')
        
        # 保存密钥到文件
        echo "$KEY_PUB" > "$server_dir/id_ed25519.pub"
        echo "$KEY_PRIV" > "$server_dir/id_ed25519"
        
        # 设置文件权限
        chmod 600 "$server_dir/id_ed25519"
        chmod 644 "$server_dir/id_ed25519.pub"
        
        log_success "密钥对生成并保存完成"
        log_info "公钥: $KEY_PUB"
        log_info "私钥: ${KEY_PRIV:0:20}..."
    else
        log_error "密钥对生成失败，使用默认密钥"
        # 使用环境变量方式
        KEY_PUB=""
        KEY_PRIV=""
    fi
    
    # 清理临时文件
    rm -f /tmp/rustdesk_keys
}

# 生成随机密码
generate_password() {
    local length=12
    tr -dc 'A-Za-z0-9!@#$%' < /dev/urandom | head -c $length
}

# 检查端口占用情况
check_ports_availability() {
    local ports=("21114" "21115" "21116" "21117" "21118" "21119")
    
    log_info "检查端口占用情况..."
    
    for port in "${ports[@]}"; do
        if ! check_port "$port"; then
            log_warning "端口 $port 可能被占用，继续部署但可能启动失败"
        else
            log_info "端口 $port 可用"
        fi
    done
    
    # 特别检查 21116 端口
    if ! check_port "21116"; then
        log_warning "⚠️  关键端口 21116 被占用，这可能影响 RustDesk ID 服务"
    fi
}

# 获取用户输入
get_user_input() {
    local default_project="rustdesk-server"
    local default_port="21114"
    
    # 读取项目名称
    while true; do
        read -p "请输入项目名称（默认: $default_project）: " input_project
        project_name=$(echo "$input_project" | xargs)
        project_name=${project_name:-$default_project}
        
        # 验证项目名称（只允许字母、数字、连字符）
        if [[ "$project_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            log_error "项目名称只能包含字母、数字、连字符和下划线"
        fi
    done
    
    # 读取端口
    while true; do
        read -p "请输入主服务端口（默认: $default_port）: " input_port
        port=$(echo "$input_port" | xargs)
        port=${port:-$default_port}
        
        # 验证端口
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]; then
            break
        else
            log_error "端口号必须是 1024-65535 之间的数字"
        fi
    done
    
    # 询问是否使用随机密码
    read -p "是否生成随机管理员密码？(y/N): " use_random_pwd
    if [[ "$use_random_pwd" =~ ^[Yy]$ ]]; then
        admin_password=$(generate_password)
        log_info "已生成随机密码"
    else
        while true; do
            read -sp "请输入管理员密码（最少8位）: " admin_password
            echo
            if [ -n "$admin_password" ] && [ ${#admin_password} -ge 8 ]; then
                break
            else
                log_error "密码不能为空且至少8位"
            fi
        done
    fi
    
    # 获取本机IP
    local_ip=$(hostname -I | awk '{print $1}')
    public_ip=$(curl -s --connect-timeout 5 ifconfig.me || echo "无法获取公网IP")
    
    echo
    log_info "配置摘要:"
    log_info "项目名称: $project_name"
    log_info "服务端口: $port"
    log_info "管理员密码: ${admin_password:0:4}******"
    log_info "本地IP: $local_ip"
    log_info "公网IP: $public_ip"
    echo
    
    read -p "确认开始部署？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "部署已取消"
        exit 0
    fi
}

# 生成 Docker Compose 配置文件
generate_compose_file() {
    local project_name="$1"
    local port="$2"
    local admin_password="$3"
    local key_pub="$4"
    local key_priv="$5"
    
    # 生成 JWT 密钥
    local jwt_key=$(openssl rand -base64 32 2>/dev/null || echo "default_jwt_key_$(date +%s)")
    
    local file_path="/data/rustdesk/docker-compose.yaml"
    
    # 如果密钥为空，则不设置密钥环境变量，让容器自己生成
    local key_envs=""
    if [[ -n "$key_pub" && -n "$key_priv" ]]; then
        key_envs="      - KEY_PUB=${key_pub}
      - KEY_PRIV=${key_priv}"
    fi
    
    cat > "$file_path" << EOF
# RustDesk Server 配置
# 生成时间: $(date)
# 项目名称: $project_name
# 注意: 此配置强制所有连接通过服务器中转

networks:
  rustdesk-net:
    driver: bridge

services:
  rustdesk-server:
    container_name: ${project_name}-rustdesk
    hostname: ${project_name}-server
    image: lejianwen/rustdesk-server-s6:latest
    ports:
      - "${port}:21114"    # API 服务器
      - "21115:21115"      # 其他服务
      - "21116:21116"      # ID 服务器
      - "21117:21117"      # 中继服务器
      - "21118:21118"      # 其他服务
      - "21119:21119"      # 其他服务
      - "21116:21116/udp"  # UDP 端口
    environment:
      - RELAY=${local_ip}
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=n
      - TZ=Asia/Shanghai
      # 强制所有连接通过中继服务器
      - ALWAYS_USE_RELAY=Y
      # 密钥配置（如果提供了密钥）
${key_envs}
      # API 配置
      - RUSTDESK_API_RUSTDESK_ID_SERVER=127.0.0.1:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=127.0.0.1:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://127.0.0.1:21114
      - RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=${jwt_key}
      # 数据库配置
      - DB_URL=/db/db_v2.sqlite3
    volumes:
      - /data/rustdesk/server:/data
      - /data/rustdesk/api:/app/data
      - /data/rustdesk/db:/db
    networks:
      - rustdesk-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:21114"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF

    log_success "Docker Compose 配置文件已生成: $file_path"
}

# 部署服务
deploy_service() {
    local project_name="$1"
    local admin_password="$2"
    local file_path="/data/rustdesk/docker-compose.yaml"
    
    log_info "开始部署 RustDesk 服务..."
    
    # 使用 docker-compose 或 docker compose
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    # 停止并删除现有容器（如果存在）
    if docker ps -a --filter "name=${project_name}-rustdesk" | grep -q "${project_name}-rustdesk"; then
        log_info "停止并删除现有容器..."
        cd /data/rustdesk
        sudo $compose_cmd -f "$file_path" down || true
    fi
    
    # 部署服务
    cd /data/rustdesk
    sudo $compose_cmd -f "$file_path" up -d
    
    log_info "等待服务启动..."
    
    # 等待服务启动
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --filter "name=${project_name}-rustdesk" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
            log_success "RustDesk 服务启动成功"
            break
        fi
        
        log_info "等待服务启动... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "服务启动超时，请检查日志"
        docker logs "${project_name}-rustdesk"
        exit 1
    fi
    
    # 等待 API 服务完全就绪
    sleep 10
    
    # 重置管理员密码
    log_info "设置管理员密码..."
    if docker exec "${project_name}-rustdesk" sh -c "./apimain reset-admin-pwd \"$admin_password\""; then
        log_success "管理员密码设置成功"
    else
        log_warning "密码设置失败，可能需要手动设置"
        log_info "请手动执行: docker exec ${project_name}-rustdesk ./apimain reset-admin-pwd \"YOUR_PASSWORD\""
    fi
    
    sleep 2
}

# 显示部署结果
show_deployment_info() {
    local project_name="$1"
    local port="$2"
    local admin_password="$3"
    local key_pub="$4"
    
    local local_ip=$(hostname -I | awk '{print $1}')
    local public_ip=$(curl -s --connect-timeout 5 ifconfig.me || echo "无法获取公网IP")
    
    echo
    log_success "🎉 RustDesk 部署完成！"
    echo
    echo "=================== 访问信息 ==================="
    echo -e "本地访问: ${GREEN}http://${local_ip}:${port}${NC}"
    if [ "$public_ip" != "无法获取公网IP" ]; then
        echo -e "公网访问: ${GREEN}http://${public_ip}:${port}${NC}"
    fi
    echo
    echo "=================== 账号信息 ==================="
    echo -e "管理员账号: ${GREEN}admin${NC}"
    echo -e "管理员密码: ${GREEN}${admin_password}${NC}"
    echo
    if [ -n "$key_pub" ]; then
        echo "=================== 密钥信息 ==================="
        echo -e "公钥 (KEY_PUB): ${GREEN}${key_pub}${NC}"
        echo -e "私钥文件: ${GREEN}/data/rustdesk/server/id_ed25519${NC}"
        echo -e "公钥文件: ${GREEN}/data/rustdesk/server/id_ed25519.pub${NC}"
        echo
    fi
    echo "=================== 连接配置 ==================="
    echo -e "连接模式: ${YELLOW}强制服务器中转${NC}"
    echo -e "ID 服务器: ${GREEN}${local_ip}:21116${NC}"
    echo -e "中继服务器: ${GREEN}${local_ip}:21117${NC}"
    echo
    echo "=================== 管理命令 ==================="
    echo -e "查看服务状态: ${YELLOW}docker ps -f name=${project_name}${NC}"
    echo -e "查看服务日志: ${YELLOW}docker logs ${project_name}-rustdesk${NC}"
    echo -e "停止服务: ${YELLOW}cd /data/rustdesk && docker compose down${NC}"
    echo -e "重启服务: ${YELLOW}cd /data/rustdesk && docker compose restart${NC}"
    echo "================================================"
    echo
    log_warning "请确保防火墙已开放端口: ${port}, 21115-21119"
    if [ -n "$key_pub" ]; then
        log_warning "客户端连接时需要配置使用上述公钥"
    fi
}

# 验证部署
verify_deployment() {
    local project_name="$1"
    local port="$2"
    
    log_info "验证部署结果..."
    
    # 检查容器状态
    if docker ps --filter "name=${project_name}-rustdesk" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
        log_success "容器运行正常"
    else
        log_error "容器未运行"
        return 1
    fi
    
    # 等待服务完全启动
    sleep 5
    
    # 检查 API 服务
    if curl -s --connect-timeout 10 "http://localhost:${port}" > /dev/null; then
        log_success "API 服务访问正常"
    else
        log_warning "API 服务访问异常，请检查日志"
    fi
    
    # 检查关键服务
    if docker exec "${project_name}-rustdesk" pgrep hbbs > /dev/null; then
        log_success "hbbs 服务运行正常"
    else
        log_warning "hbbs 服务异常"
    fi
    
    if docker exec "${project_name}-rustdesk" pgrep hbbr > /dev/null; then
        log_success "hbbr 服务运行正常"
    else
        log_warning "hbbr 服务异常"
    fi
}

# 主函数
main() {
    echo
    log_info "开始 RustDesk 服务器部署"
    echo "========================================"
    
    # 检查 Docker
    check_docker
    
    # 创建目录
    create_directories
    
    # 检查端口
    check_ports_availability
    
    # 获取用户输入
    get_user_input
    
    # 生成密钥对
    generate_keypair
    
    # 生成配置文件
    generate_compose_file "$project_name" "$port" "$admin_password" "$KEY_PUB" "$KEY_PRIV"
    
    # 部署服务
    deploy_service "$project_name" "$admin_password"
    
    # 验证部署
    verify_deployment "$project_name" "$port"
    
    # 显示部署结果
    show_deployment_info "$project_name" "$port" "$admin_password" "$KEY_PUB"
    
    log_success "部署脚本执行完成"
}

# 脚本入口
main "$@"
