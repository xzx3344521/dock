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

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
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
    local dirs=("/data" "/boot/脚本" "/data/rustdesk/server" "/data/rustdesk/api")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
            log_info "创建目录: $dir"
        else
            log_info "目录已存在: $dir"
        fi
    done
}

# 生成随机密码
generate_password() {
    local length=12
    tr -dc 'A-Za-z0-9!@#$%' < /dev/urandom | head -c $length
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
            read -sp "请输入管理员密码: " admin_password
            echo
            if [ -n "$admin_password" ]; then
                break
            else
                log_error "密码不能为空"
            fi
        done
    fi
    
    # 获取本机IP
    local_ip=$(hostname -I | awk '{print $1}')
    public_ip=$(curl -s ifconfig.me || echo "无法获取公网IP")
    
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
    local file_path="/boot/脚本/rustdesk.yaml"
    local project_name="$1"
    local port="$2"
    local admin_password="$3"
    
    # 生成 JWT 密钥
    local jwt_key=$(openssl rand -base64 32 2>/dev/null || echo "default_jwt_key_$(date +%s)")
    
    cat > "$file_path" << EOF
# RustDesk Server 配置
# 生成时间: $(date)
# 项目名称: $project_name

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
      - RELAY=127.0.0.1
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=n
      - TZ=Asia/Shanghai
      - RUSTDESK_API_RUSTDESK_ID_SERVER=127.0.0.1:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=127.0.0.1:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://127.0.0.1:21114
      - RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=${jwt_key}
    volumes:
      - /data/rustdesk/server:/data
      - /data/rustdesk/api:/app/data
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
    local file_path="/boot/脚本/rustdesk.yaml"
    
    log_info "开始部署 RustDesk 服务..."
    
    # 使用 docker-compose 或 docker compose
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    # 部署服务
    sudo $compose_cmd -p "$project_name" -f "$file_path" up -d
    
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
    
    # 重置管理员密码
    log_info "设置管理员密码..."
    if docker exec "${project_name}-rustdesk" sh -c "./apimain reset-admin-pwd \"$admin_password\""; then
        log_success "管理员密码设置成功"
    else
        log_warning "密码设置失败，可能需要手动设置"
    fi
    
    sleep 2
}

# 显示部署结果
show_deployment_info() {
    local project_name="$1"
    local port="$2"
    local admin_password="$3"
    
    local local_ip=$(hostname -I | awk '{print $1}')
    
    echo
    log_success "🎉 RustDesk 部署完成！"
    echo
    echo "=================== 访问信息 ==================="
    echo -e "本地访问: ${GREEN}http://${local_ip}:${port}${NC}"
    echo -e "公网访问: ${GREEN}请使用您的公网IP:${port}${NC}"
    echo
    echo "=================== 账号信息 ==================="
    echo -e "管理员账号: ${GREEN}admin${NC}"
    echo -e "管理员密码: ${GREEN}${admin_password}${NC}"
    echo
    echo "=================== 管理命令 ==================="
    echo -e "查看服务状态: ${YELLOW}docker ps -f name=${project_name}${NC}"
    echo -e "查看服务日志: ${YELLOW}docker logs ${project_name}-rustdesk${NC}"
    echo -e "停止服务: ${YELLOW}sudo docker compose -p ${project_name} down${NC}"
    echo -e "重启服务: ${YELLOW}sudo docker compose -p ${project_name} restart${NC}"
    echo "================================================"
    echo
    log_warning "请确保防火墙已开放端口: ${port}, 21115-21119"
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
    
    # 获取用户输入
    get_user_input
    
    # 生成配置文件
    generate_compose_file "$project_name" "$port" "$admin_password"
    
    # 部署服务
    deploy_service "$project_name" "$admin_password"
    
    # 显示部署结果
    show_deployment_info "$project_name" "$port" "$admin_password"
    
    log_success "部署脚本执行完成"
}

# 脚本入口
main "$@"
