#!/bin/bash

# 设置错误处理
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 日志函数
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检测 Docker Compose 命令
detect_compose_command() {
    log_info "检测 Docker Compose 命令..."
    
    # 优先使用 docker compose (新版本)
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
        log_success "使用 Docker Compose Plugin (docker compose)"
        return 0
    # 检查 docker-compose (旧版本)
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
        log_success "使用 Docker Compose Standalone (docker-compose)"
        return 0
    else
        log_error "未找到 Docker Compose 命令"
        log_info "请安装 Docker Compose:"
        log_info "1. Docker Compose Plugin: apt-get install docker-compose-plugin"
        log_info "2. 或 Docker Compose Standalone: curl -L \"https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose"
        return 1
    fi
}

# 检查 Docker 是否安装
check_docker() {
    log_info "检查 Docker 环境..."
    
    if ! command -v docker &>/dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker 服务异常，请检查 Docker 状态"
        exit 1
    fi

    # 检测 Docker Compose 命令
    if ! detect_compose_command; then
        exit 1
    fi

    log_success "Docker 环境检查通过"
}

# 检查端口是否被占用
check_port() {
    local port=$1
    local protocol=${2:-tcp}
    
    if [[ "$port" -lt 1024 || "$port" -gt 65535 ]]; then
        log_error "端口号 $port 超出范围 (1024-65535)"
        return 1
    fi
    
    local port_in_use=false
    
    # 检查端口占用
    if command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":${port}[[:space:]]"; then
            log_warning "端口 $port 被占用 (netstat)"
            port_in_use=true
        fi
    fi
    
    if command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":${port}[[:space:]]"; then
            log_warning "端口 $port 被占用 (ss)"
            port_in_use=true
        fi
    fi

    # 检查 Docker 容器
    if command -v docker &>/dev/null; then
        if docker ps --format "table {{.Ports}}" | grep -q ":${port}->"; then
            log_warning "端口 $port 被 Docker 容器占用"
            port_in_use=true
        fi
    fi
    
    if [[ "$port_in_use" == "true" ]]; then
        return 1
    fi
    
    return 0
}

# 创建目录结构
create_directories() {
    local dirs=("/data/rustdesk/server" "/data/rustdesk/api" "/data/rustdesk/db")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            log_info "创建目录: $dir"
        else
            log_info "目录已存在: $dir"
        fi
    done

    sudo chmod 755 /data/rustdesk
    sudo chmod 755 /data/rustdesk/server
    sudo chmod 755 /data/rustdesk/api
    sudo chmod 755 /data/rustdesk/db

    if [[ "$(id -u)" -ne 0 ]]; then
        sudo chown -R "$(id -u):$(id -g)" /data/rustdesk
    fi
}

# 修复密钥对问题
fix_keypair() {
    local server_dir="/data/rustdesk/server"
    
    log_info "检查并修复密钥对问题..."
    
    # 备份现有密钥（如果存在）
    if [[ -f "$server_dir/id_ed25519" || -f "$server_dir/id_ed25519.pub" ]]; then
        log_warning "发现现有密钥文件，进行备份..."
        local backup_dir="/data/rustdesk/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -f "$server_dir/id_ed25519" "$backup_dir/" 2>/dev/null || true
        cp -f "$server_dir/id_ed25519.pub" "$backup_dir/" 2>/dev/null || true
        log_info "旧密钥已备份到: $backup_dir"
    fi
    
    # 删除现有密钥文件
    rm -f "$server_dir/id_ed25519" "$server_dir/id_ed25519.pub"
    
    # 生成新的密钥对
    log_info "生成新的 RustDesk 密钥对..."
    
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if docker run --rm --entrypoint /usr/bin/rustdesk-utils lejianwen/rustdesk-server-s6:latest genkeypair > /tmp/rustdesk_keys 2>/dev/null; then
            # 解析生成的密钥
            KEY_PUB=$(grep "Public Key:" /tmp/rustdesk_keys | awk '{print $3}')
            KEY_PRIV=$(grep "Secret Key:" /tmp/rustdesk_keys | awk '{print $3}')
            
            # 验证密钥格式
            if [[ -n "$KEY_PUB" && -n "$KEY_PRIV" ]]; then
                # 保存密钥到文件
                echo "$KEY_PUB" > "$server_dir/id_ed25519.pub"
                echo "$KEY_PRIV" > "$server_dir/id_ed25519"
                
                # 设置文件权限
                chmod 600 "$server_dir/id_ed25519"
                chmod 644 "$server_dir/id_ed25519.pub"
                
                # 验证密钥文件
                if [[ -f "$server_dir/id_ed25519" && -f "$server_dir/id_ed25519.pub" ]]; then
                    local pub_content=$(cat "$server_dir/id_ed25519.pub")
                    local priv_content=$(cat "$server_dir/id_ed25519")
                    
                    if [[ "$pub_content" == "$KEY_PUB" && "$priv_content" == "$KEY_PRIV" ]]; then
                        log_success "密钥对生成并验证成功"
                        log_info "公钥: $KEY_PUB"
                        log_info "私钥: ${KEY_PRIV:0:20}..."
                        rm -f /tmp/rustdesk_keys
                        return 0
                    fi
                fi
            fi
        fi
        
        retry_count=$((retry_count + 1))
        log_warning "密钥生成失败，重试第 $retry_count 次..."
        sleep 2
    done
    
    log_error "密钥对生成失败，使用空密钥（容器将自行生成）"
    KEY_PUB=""
    KEY_PRIV=""
    rm -f /tmp/rustdesk_keys
    return 1
}

# 生成随机密码
generate_password() {
    local length=12
    tr -dc 'A-Za-z0-9!@#$%' < /dev/urandom | head -c $length
}

# 检查端口占用情况
check_ports_availability() {
    local ports=("$api_port" "$hbbs_port" "$hbbr_port" "21115" "21118" "21119")
    
    log_info "检查端口占用情况..."
    
    for port in "${ports[@]}"; do
        if ! check_port "$port"; then
            log_warning "端口 $port 被占用，可能影响服务启动"
        else
            log_info "端口 $port 可用"
        fi
    done
}

# 获取用户输入
get_user_input() {
    local default_project="rustdesk-server"
    local default_api_port="21114"
    local default_hbbs_port="21116"
    local default_hbbr_port="21117"

    # 读取项目名称
    while true; do
        read -p "请输入项目名称（默认: $default_project）: " input_project
        project_name=$(echo "$input_project" | xargs)
        project_name=${project_name:-$default_project}
        
        if [[ "$project_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            log_error "项目名称只能包含字母、数字、连字符和下划线"
        fi
    done

    # 读取API端口
    while true; do
        read -p "请输入API服务端口（默认: $default_api_port）: " input_port
        api_port=$(echo "$input_port" | xargs)
        api_port=${api_port:-$default_api_port}
        
        if [[ "$api_port" =~ ^[0-9]+$ ]] && [[ "$api_port" -ge 1024 && "$api_port" -le 65535 ]]; then
            if ! check_port "$api_port"; then
                log_warning "端口 $api_port 已被占用"
                read -p "是否继续使用此端口？(y/N): " use_occupied_port
                if [[ "$use_occupied_port" =~ ^[Yy]$ ]]; then
                    break
                fi
            else
                break
            fi
        else
            log_error "端口号必须是 1024-65535 之间的数字"
        fi
    done

    # 读取ID服务器端口
    while true; do
        read -p "请输入ID服务器端口（默认: $default_hbbs_port）: " input_port
        hbbs_port=$(echo "$input_port" | xargs)
        hbbs_port=${hbbs_port:-$default_hbbs_port}
        
        if [[ "$hbbs_port" =~ ^[0-9]+$ ]] && [[ "$hbbs_port" -ge 1024 && "$hbbs_port" -le 65535 ]]; then
            if ! check_port "$hbbs_port"; then
                log_warning "端口 $hbbs_port 已被占用"
                read -p "是否继续使用此端口？(y/N): " use_occupied_port
                if [[ "$use_occupied_port" =~ ^[Yy]$ ]]; then
                    break
                fi
            else
                break
            fi
        else
            log_error "端口号必须是 1024-65535 之间的数字"
        fi
    done

    # 读取中继服务器端口
    while true; do
        read -p "请输入中继服务器端口（默认: $default_hbbr_port）: " input_port
        hbbr_port=$(echo "$input_port" | xargs)
        hbbr_port=${hbbr_port:-$default_hbbr_port}
        
        if [[ "$hbbr_port" =~ ^[0-9]+$ ]] && [[ "$hbbr_port" -ge 1024 && "$hbbr_port" -le 65535 ]]; then
            if ! check_port "$hbbr_port"; then
                log_warning "端口 $hbbr_port 已被占用"
                read -p "是否继续使用此端口？(y/N): " use_occupied_port
                if [[ "$use_occupied_port" =~ ^[Yy]$ ]]; then
                    break
                fi
            else
                break
            fi
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
            read -sp "请输入管理员密码（最少 8 位）: " admin_password
            echo
            if [[ -n "$admin_password" && ${#admin_password} -ge 8 ]]; then
                read -sp "请确认管理员密码: " admin_password_confirm
                echo
                if [[ "$admin_password" == "$admin_password_confirm" ]]; then
                    break
                else
                    log_error "两次输入的密码不一致"
                fi
            else
                log_error "密码不能为空且至少 8 位"
            fi
        done
    fi

    # 获取本机 IP
    local_ip=$(hostname -I | awk '{print $1}')
    public_ip=$(curl -s --connect-timeout 5 ifconfig.me || echo "无法获取公网IP")

    echo
    log_info "配置摘要:"
    log_info "项目名称: $project_name"
    log_info "API服务端口: $api_port"
    log_info "ID服务器端口: $hbbs_port"
    log_info "中继服务器端口: $hbbr_port"
    log_info "管理员密码: ${admin_password:0:4}******"
    log_info "本地 IP: $local_ip"
    log_info "公网 IP: $public_ip"
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
    local api_port="$2"
    local hbbs_port="$3"
    local hbbr_port="$4"
    local admin_password="$5"
    local key_pub="$6"
    local key_priv="$7"
    
    # 生成 JWT 密钥
    local jwt_key=$(openssl rand -base64 32 2>/dev/null || echo "default_jwt_key_$(date +%s)")
    
    local file_path="/data/rustdesk/docker-compose.yml"
    
    # 如果密钥为空，则不设置密钥环境变量，让容器自己生成
    local key_envs=""
    if [[ -n "$key_pub" && -n "$key_priv" ]]; then
        key_envs="      - KEY_PUB=$key_pub
      - KEY_PRIV=$key_priv"
        log_info "使用自定义密钥对"
    else
        log_info "未提供密钥对，容器将自动生成"
    fi

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
      - "${api_port}:21114"   # API 服务器
      - "21115:21115"         # 其他服务
      - "${hbbs_port}:21116"  # ID 服务器 (hbbs)
      - "${hbbr_port}:21117"  # 中继服务器 (hbbr)
      - "21118:21118"         # 其他服务
      - "21119:21119"         # 其他服务
      - "${hbbs_port}:21116/udp" # UDP 端口
    environment:
      - RELAY=${local_ip}:${hbbr_port}
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=n
      - TZ=Asia/Shanghai
      # 设置中文语言
      - LANG=zh_CN.UTF-8
      - LANGUAGE=zh_CN:zh
      - LC_ALL=zh_CN.UTF-8
      # 自定义端口 - 关键配置！
      - PORT=${hbbs_port}
      - BIND_PORT=${hbbr_port}
      # 强制所有连接通过中继服务器
      - ALWAYS_USE_RELAY=Y
      # 密钥配置
$key_envs
      # API 配置
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${local_ip}:${hbbs_port}
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${local_ip}:${hbbr_port}
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://${local_ip}:${api_port}
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
      start_period: 60s
EOF

    log_success "Docker Compose 配置文件已生成: $file_path"
}

# 检查容器运行状态
check_container_health() {
    local container_name="$1"
    local max_checks=5
    local check_interval=5
    
    log_info "检查容器 $container_name 运行状态..."
    
    for ((i=1; i<=max_checks; i++)); do
        # 检查容器是否存在
        if ! docker ps -a | grep -q "$container_name"; then
            log_error "容器 $container_name 不存在"
            return 1
        fi
        
        # 检查容器状态
        local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
        
        case "$status" in
            "running")
                # 检查关键进程
                if docker exec "$container_name" pgrep hbbs >/dev/null 2>&1 && \
                   docker exec "$container_name" pgrep hbbr >/dev/null 2>&1; then
                    log_success "容器运行正常 (关键进程运行中)"
                    
                    # 额外检查服务是否真正就绪
                    if docker exec "$container_name" curl -f http://localhost:21114 >/dev/null 2>&1; then
                        log_success "API 服务就绪"
                        return 0
                    else
                        log_info "等待API服务就绪... ($i/$max_checks)"
                    fi
                elif [[ $i -gt 5 ]]; then
                    log_info "等待关键进程启动... ($i/$max_checks)"
                fi
                ;;
            "exited")
                local exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$container_name")
                log_error "容器已退出，退出码: $exit_code"
                log_info "查看容器日志:"
                docker logs "$container_name" | tail -30
                return 1
                ;;
            "restarting")
                log_info "容器正在重启... ($i/$max_checks)"
                ;;
            *)
                log_error "容器状态异常: $status"
                return 1
                ;;
        esac
        
        if [[ $i -eq $max_checks ]]; then
            log_warning "容器状态检查超时，但继续部署流程"
            return 0
        fi
        
        sleep $check_interval
    done
    
    return 0
}

# 部署服务
deploy_service() {
    local project_name="$1"
    local admin_password="$2"
    local file_path="/data/rustdesk/docker-compose.yml"
    
    log_info "开始部署 RustDesk 服务..."
    
    # 停止并删除现有容器（如果存在）
    if docker ps -a --filter "name=${project_name}-rustdesk" | grep -q "${project_name}-rustdesk"; then
        log_info "停止并删除现有容器..."
        cd /data/rustdesk
        $COMPOSE_CMD -f "$file_path" down || true
        sleep 5
    fi
    
    # 部署服务
    cd /data/rustdesk
    log_info "启动服务..."
    log_info "使用命令: $COMPOSE_CMD -f \"$file_path\" up -d"
    
    if ! $COMPOSE_CMD -f "$file_path" up -d; then
        log_error "服务启动失败"
        
        # 提供故障排除建议
        log_info "故障排除建议:"
        log_info "1. 检查 Docker 服务状态: systemctl status docker"
        log_info "2. 检查当前用户是否有 Docker 权限"
        log_info "3. 尝试手动启动: cd /data/rustdesk && $COMPOSE_CMD up -d"
        return 1
    fi
    
    sleep 10
    
    # 检查容器运行状态
    if ! check_container_health "${project_name}-rustdesk"; then
        log_warning "容器启动过程中遇到问题，尝试继续配置..."
    fi
    
    # 等待服务完全启动
    log_info "等待服务初始化完成..."
    sleep 15
    
    # 重置管理员密码
    log_info "设置管理员密码..."
    local password_retries=5
    local password_success=false
    
    for ((i=1; i<=password_retries; i++)); do
        if docker exec "${project_name}-rustdesk" sh -c "./apimain reset-admin-pwd \"$admin_password\"" 2>/dev/null; then
            log_success "管理员密码设置成功"
            password_success=true
            break
        else
            log_warning "密码设置失败，重试第 $i 次... (等待服务完全启动)"
            sleep 10
        fi
    done
    
    if [[ "$password_success" == "false" ]]; then
        log_warning "密码设置失败，可能需要手动设置"
        log_info "请手动执行: docker exec ${project_name}-rustdesk ./apimain reset-admin-pwd \"$admin_password\""
    fi
    
    return 0
}

# 验证服务连通性
test_service_connectivity() {
    local api_port="$1"
    local hbbs_port="$2"
    local hbbr_port="$3"
    
    log_info "测试服务连通性..."
    
    # 测试API服务
    if curl -s --connect-timeout 10 "http://localhost:${api_port}" > /dev/null; then
        log_success "API 服务连通正常"
    else
        log_warning "API 服务连通异常"
    fi
    
    # 测试端口连通性
    if command -v nc &>/dev/null; then
        if nc -z -w 3 localhost "$hbbs_port"; then
            log_success "ID服务器端口 $hbbs_port 连通正常"
        else
            log_warning "ID服务器端口 $hbbs_port 连通异常"
        fi
        
        if nc -z -w 3 localhost "$hbbr_port"; then
            log_success "中继服务器端口 $hbbr_port 连通正常"
        else
            log_warning "中继服务器端口 $hbbr_port 连通异常"
        fi
    fi
}

# 验证部署
verify_deployment() {
    local project_name="$1"
    local api_port="$2"
    local hbbs_port="$3"
    local hbbr_port="$4"
    
    log_info "验证部署结果..."
    
    # 检查容器状态
    if docker ps --filter "name=${project_name}-rustdesk" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
        log_success "容器运行正常"
    else
        log_error "容器未运行"
        return 1
    fi
    
    sleep 10
    
    # 检查关键服务进程
    if docker exec "${project_name}-rustdesk" pgrep hbbs > /dev/null 2>&1; then
        log_success "hbbs (ID服务器) 运行正常"
    else
        log_warning "hbbs (ID服务器) 异常"
    fi
    
    if docker exec "${project_name}-rustdesk" pgrep hbbr > /dev/null 2>&1; then
        log_success "hbbr (中继服务器) 运行正常"
    else
        log_warning "hbbr (中继服务器) 异常"
    fi
    
    # 测试服务连通性
    test_service_connectivity "$api_port" "$hbbs_port" "$hbbr_port"
    
    # 检查端口监听情况
    log_info "检查端口监听状态..."
    if netstat -tuln | grep -q ":${hbbs_port}[[:space:]]"; then
        log_success "ID服务器端口 $hbbs_port 监听正常"
    else
        log_warning "ID服务器端口 $hbbs_port 未监听"
    fi
    
    if netstat -tuln | grep -q ":${hbbr_port}[[:space:]]"; then
        log_success "中继服务器端口 $hbbr_port 监听正常"
    else
        log_warning "中继服务器端口 $hbbr_port 未监听"
    fi
    
    return 0
}

# 显示部署结果
show_deployment_info() {
    local project_name="$1"
    local api_port="$2"
    local hbbs_port="$3"
    local hbbr_port="$4"
    local admin_password="$5"
    local key_pub="$6"
    
    local local_ip=$(hostname -I | awk '{print $1}')
    local public_ip=$(curl -s --connect-timeout 5 ifconfig.me || echo "无法获取公网IP")
    
    echo
    log_success "🎉 RustDesk 部署完成！"
    echo
    echo "=================== 访问信息 ==================="
    echo -e "Web管理界面: ${GREEN}http://${local_ip}:${api_port}${NC}"
    if [[ "$public_ip" != "无法获取公网IP" ]]; then
        echo -e "公网访问: ${GREEN}http://${public_ip}:${api_port}${NC}"
    fi
    echo
    echo "=================== 账号信息 ==================="
    echo -e "管理员账号: ${GREEN}admin${NC}"
    echo -e "管理员密码: ${GREEN}${admin_password}${NC}"
    echo
    
    # 重新读取实际的公钥
    local actual_pub_key=""
    if [[ -f "/data/rustdesk/server/id_ed25519.pub" ]]; then
        actual_pub_key=$(cat "/data/rustdesk/server/id_ed25519.pub")
    fi
    
    if [[ -n "$actual_pub_key" ]]; then
        echo "=================== 密钥信息 ==================="
        echo -e "公钥 (KEY): ${GREEN}${actual_pub_key}${NC}"
        echo
    fi
    
    echo "=================== 服务器配置 ==================="
    echo -e "ID 服务器: ${GREEN}${local_ip}:${hbbs_port}${NC}"
    echo -e "中继服务器: ${GREEN}${local_ip}:${hbbr_port}${NC}"
    echo -e "API 服务器: ${GREEN}http://${local_ip}:${api_port}${NC}"
    echo
    echo "=================== 客户端配置步骤 ==================="
    echo "1. 打开 RustDesk 客户端"
    echo "2. 点击 ID/中继服务器 设置"
    echo "3. 填写以下信息:"
    echo "   - ID 服务器: ${local_ip}:${hbbs_port}"
    echo "   - 中继服务器: ${local_ip}:${hbbr_port}"
    if [[ -n "$actual_pub_key" ]]; then
        echo "   - Key: ${actual_pub_key}"
    fi
    echo "4. 点击 '应用' 保存"
    echo "5. 重启 RustDesk 客户端"
    echo "==================================================="
    echo
    echo "=================== 管理命令 ==================="
    echo -e "查看服务状态: ${YELLOW}docker ps -f name=${project_name}${NC}"
    echo -e "查看服务日志: ${YELLOW}docker logs ${project_name}-rustdesk${NC}"
    echo -e "停止服务: ${YELLOW}cd /data/rustdesk && $COMPOSE_CMD down${NC}"
    echo -e "重启服务: ${YELLOW}cd /data/rustdesk && $COMPOSE_CMD restart${NC}"
    echo "================================================"
    echo
    log_warning "请确保防火墙已开放以下端口:"
    echo -e "  - API服务端口: ${YELLOW}${api_port}${NC}"
    echo -e "  - ID服务器端口: ${YELLOW}${hbbs_port}${NC}"
    echo -e "  - 中继服务器端口: ${YELLOW}${hbbr_port}${NC}"
    echo -e "  - 其他端口: ${YELLOW}21115, 21118, 21119${NC}"
    
    # 显示诊断信息
    echo
    echo "=================== 诊断信息 ==================="
    log_info "如果客户端显示'未就绪'，请检查:"
    echo "1. 防火墙端口是否开放"
    echo "2. 客户端配置是否正确"
    echo "3. 服务日志: docker logs ${project_name}-rustdesk"
    echo "================================================"
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
    
    # 检查端口
    check_ports_availability
    
    # 修复密钥对问题（强制重新生成）
    fix_keypair
    
    # 生成配置文件
    generate_compose_file "$project_name" "$api_port" "$hbbs_port" "$hbbr_port" "$admin_password" "$KEY_PUB" "$KEY_PRIV"
    
    # 部署服务
    if deploy_service "$project_name" "$admin_password"; then
        # 验证部署
        verify_deployment "$project_name" "$api_port" "$hbbs_port" "$hbbr_port"
        # 显示部署结果
        show_deployment_info "$project_name" "$api_port" "$hbbs_port" "$hbbr_port" "$admin_password" "$KEY_PUB"
        log_success "部署脚本执行完成"
        
        # 显示最终检查
        echo
        log_info "最终状态检查:"
        docker ps -f "name=${project_name}-rustdesk"
    else
        log_error "部署失败，请检查上述错误信息"
        log_info "故障排除建议:"
        log_info "1. 检查 Docker 日志: docker logs ${project_name}-rustdesk"
        log_info "2. 检查端口占用: netstat -tulpn | grep 2111"
        log_info "3. 检查防火墙设置"
        log_info "4. 尝试手动重启: cd /data/rustdesk && $COMPOSE_CMD down && $COMPOSE_CMD up -d"
        exit 1
    fi
}

# 脚本入口
main "$@"
