#!/bin/bash

# 设置错误处理
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
SCRIPT_DIR="/data/rustdesk"
FIXED_KEY_PUB="Doo0qYGYNSEzxoZRPrnV9AtkeX5FFLjcweiH4K1nIJM="
FIXED_KEY_PRIV=""

# 日志函数
log_info() { echo -e "${BLUE}[信息]${NC} $1"; }
log_success() { echo -e "${GREEN}[成功]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
log_error() { echo -e "${RED}[错误]${NC} $1"; }

# 简单输出函数（不带颜色，用于复杂输出）
echo_info() { echo "[信息] $1"; }
echo_success() { echo "[成功] $1"; }
echo_warning() { echo "[警告] $1"; }
echo_error() { echo "[错误] $1"; }

# 安全清理函数
cleanup() {
    echo_info "执行清理操作..."
    rm -f /tmp/rustdesk_keys
    unset admin_password
}

# 信号处理
trap cleanup EXIT INT TERM

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo_error "必需命令 '$1' 未找到"
        return 1
    fi
    return 0
}

# 检查端口是否被占用
check_port() {
    local port=$1
    
    # 验证端口范围
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1024 || "$port" -gt 65535 ]]; then
        echo_error "端口号 $port 无效 (必须是1024-65535)"
        return 2
    fi
    
    # 检查端口占用
    local port_in_use=false
    
    if command -v netstat &>/dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            echo_warning "端口 $port 被占用 (netstat)"
            port_in_use=true
        fi
    fi
    
    if command -v ss &>/dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            echo_warning "端口 $port 被占用 (ss)"
            port_in_use=true
        fi
    fi

    # 检查 Docker 容器占用
    if command -v docker &>/dev/null; then
        if docker ps --format "table {{.Ports}}" 2>/dev/null | grep -q ":${port}->"; then
            echo_warning "端口 $port 被 Docker 容器占用"
            port_in_use=true
        fi
    fi
    
    if [[ "$port_in_use" == "true" ]]; then
        return 1
    fi
    
    return 0
}

# 检查 Docker 环境
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

    # 检查 Docker Compose
    local compose_cmd=""
    if command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
        log_info "使用 docker-compose"
    elif docker compose version &>/dev/null; then
        compose_cmd="docker compose"
        log_info "使用 docker compose"
    else
        log_error "Docker Compose 未安装"
        exit 1
    fi

    log_success "Docker 环境检查通过"
    echo "$compose_cmd"
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."
    
    local dirs=("$SCRIPT_DIR/server" "$SCRIPT_DIR/api" "$SCRIPT_DIR/db")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            log_info "创建目录: $dir"
        else
            log_info "目录已存在: $dir"
        fi
    done

    # 设置权限
    sudo chmod 755 "$SCRIPT_DIR"
    sudo chmod 755 "$SCRIPT_DIR/server"
    sudo chmod 755 "$SCRIPT_DIR/api"
    sudo chmod 755 "$SCRIPT_DIR/db"

    # 设置所有权
    if [[ "$(id -u)" -ne 0 ]]; then
        sudo chown -R "$(id -u):$(id -g)" "$SCRIPT_DIR"
    fi
}

# 固定密钥设置函数
setup_fixed_key() {
    local server_dir="$SCRIPT_DIR/server"
    
    log_info "设置固定客户端密钥..."
    
    # 备份现有密钥
    if [[ -f "$server_dir/id_ed25519" || -f "$server_dir/id_ed25519.pub" ]]; then
        local backup_dir="$SCRIPT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -f "$server_dir/id_ed25519" "$backup_dir/" 2>/dev/null || true
        cp -f "$server_dir/id_ed25519.pub" "$backup_dir/" 2>/dev/null || true
        log_info "旧密钥备份到: $backup_dir"
    fi
    
    # 清理旧密钥
    rm -f "$server_dir/id_ed25519" "$server_dir/id_ed25519.pub"
    
    # 写入固定公钥
    echo "$FIXED_KEY_PUB" > "$server_dir/id_ed25519.pub"
    
    # 创建空的私钥文件
    touch "$server_dir/id_ed25519"
    
    # 设置文件权限
    chmod 644 "$server_dir/id_ed25519.pub"
    chmod 600 "$server_dir/id_ed25519"
    
    # 验证密钥文件
    if [[ -f "$server_dir/id_ed25519.pub" ]]; then
        local saved_key=$(cat "$server_dir/id_ed25519.pub")
        if [[ "$saved_key" == "$FIXED_KEY_PUB" ]]; then
            log_success "固定密钥设置成功"
            return 0
        else
            log_error "密钥写入验证失败"
            return 1
        fi
    else
        log_error "密钥文件创建失败"
        return 1
    fi
}

# 安全密码生成
generate_password() {
    local length=12
    tr -dc 'A-Za-z0-9@#$%^&*+' < /dev/urandom 2>/dev/null | head -c $length
}

# 获取本机IP
get_ip_address() {
    local local_ip public_ip
    
    # 获取本地IP
    local_ip=$(hostname -I | awk '{print $1}' | head -1)
    if [[ -z "$local_ip" ]]; then
        local_ip="127.0.0.1"
    fi
    
    # 获取公网IP（带超时）
    public_ip=$(curl -s --connect-timeout 3 -m 5 ifconfig.me 2>/dev/null || echo "无法获取")
    
    echo "$local_ip" "$public_ip"
}

# 验证用户输入
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "project_name")
            [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] && return 0
            echo_error "项目名称只能包含字母、数字、连字符和下划线"
            ;;
        "port")
            [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -ge 1024 && "$value" -le 65535 ]] && return 0
            echo_error "端口号必须是 1024-65535 之间的数字"
            ;;
        "password")
            [[ -n "$value" && ${#value} -ge 8 ]] && return 0
            echo_error "密码不能为空且至少 8 位"
            ;;
    esac
    return 1
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
        
        if validate_input "project_name" "$project_name"; then
            break
        fi
    done

    # 读取端口配置
    local ports=("api_port" "hbbs_port" "hbbr_port")
    local defaults=("$default_api_port" "$default_hbbs_port" "$default_hbbr_port")
    local descriptions=("API服务端口" "ID服务器端口" "中继服务器端口")
    
    for i in "${!ports[@]}"; do
        while true; do
            read -p "请输入${descriptions[i]}（默认: ${defaults[i]}）: " input_port
            local port_val=$(echo "$input_port" | xargs)
            port_val=${port_val:-${defaults[i]}}
            
            if validate_input "port" "$port_val"; then
                if check_port "$port_val"; then
                    declare -g "${ports[i]}=$port_val"
                    break
                else
                    echo_warning "端口 $port_val 已被占用"
                    read -p "是否强制使用此端口？(y/N): " use_occupied_port
                    if [[ "$use_occupied_port" =~ ^[Yy]$ ]]; then
                        declare -g "${ports[i]}=$port_val"
                        break
                    fi
                fi
            fi
        done
    done

    # 密码处理
    read -p "是否生成随机管理员密码？(y/N): " use_random_pwd
    if [[ "$use_random_pwd" =~ ^[Yy]$ ]]; then
        admin_password=$(generate_password)
        log_info "已生成随机密码"
    else
        while true; do
            read -sp "请输入管理员密码（最少 8 位）: " password1
            echo
            read -sp "请确认管理员密码: " password2
            echo
            
            if validate_input "password" "$password1" && [[ "$password1" == "$password2" ]]; then
                admin_password="$password1"
                break
            elif [[ "$password1" != "$password2" ]]; then
                echo_error "两次输入的密码不一致"
            fi
        done
    fi

    # 显示配置摘要
    local ip_info=($(get_ip_address))
    local local_ip="${ip_info[0]}"
    local public_ip="${ip_info[1]}"
    
    echo
    log_info "配置摘要:"
    log_info "项目名称: $project_name"
    log_info "API服务端口: $api_port"
    log_info "ID服务器端口: $hbbs_port"
    log_info "中继服务器端口: $hbbr_port"
    log_info "管理员密码: ${admin_password:0:2}******"
    log_info "本地 IP: $local_ip"
    log_info "公网 IP: $public_ip"
    echo
    
    read -p "确认开始部署？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "部署已取消"
        exit 0
    fi
}

# 生成 Docker Compose 配置
generate_compose_file() {
    local project_name="$1" api_port="$2" hbbs_port="$3" hbbr_port="$4"
    local admin_password="$5"
    
    local file_path="$SCRIPT_DIR/docker-compose.yml"
    local ip_info=($(get_ip_address))
    local local_ip="${ip_info[0]}"
    
    # 生成 JWT 密钥
    local jwt_key=$(openssl rand -base64 32 2>/dev/null || 
                   echo "fallback_jwt_key_$(date +%s)")

    cat > "$file_path" << EOF
# RustDesk Server 配置
# 生成时间: $(date)
# 项目名称: $project_name
# 使用固定客户端密钥

version: '3.8'

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
      - "21115:21115"         # Web客户端
      - "${hbbs_port}:21116"  # ID 服务器 (hbbs)
      - "${hbbr_port}:21117"  # 中继服务器 (hbbr)
      - "21118:21118"         # 文件传输
      - "21119:21119"         # 其他服务
      - "${hbbs_port}:21116/udp" # UDP 端口
    environment:
      - RELAY=${local_ip}:${hbbr_port}
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=n
      - TZ=Asia/Shanghai
      # 语言设置
      - LANG=zh_CN.UTF-8
      - LANGUAGE=zh_CN:zh
      - LC_ALL=zh_CN.UTF-8
      # 端口配置
      - PORT=${hbbs_port}
      - BIND_PORT=${hbbr_port}
      # 网络配置
      - ALWAYS_USE_RELAY=Y
      # 固定密钥配置
      - KEY_PUB=${FIXED_KEY_PUB}
      # API 配置
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${local_ip}:${hbbs_port}
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${local_ip}:${hbbr_port}
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://${local_ip}:${api_port}
      - RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=${jwt_key}
      # 数据库配置
      - DB_URL=/db/db_v2.sqlite3
    volumes:
      - $SCRIPT_DIR/server:/data
      - $SCRIPT_DIR/api:/app/data
      - $SCRIPT_DIR/db:/db
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

# 部署服务
deploy_service() {
    local project_name="$1" admin_password="$2"
    local compose_cmd="$3"
    local file_path="$SCRIPT_DIR/docker-compose.yml"
    
    log_info "开始部署 RustDesk 服务..."
    
    cd "$SCRIPT_DIR" || {
        log_error "无法进入目录: $SCRIPT_DIR"
        return 1
    }
    
    # 停止现有服务
    if docker ps -a --filter "name=${project_name}-rustdesk" | grep -q "${project_name}-rustdesk"; then
        log_info "停止现有服务..."
        $compose_cmd -f "$file_path" down || true
        sleep 5
    fi
    
    # 启动服务
    log_info "启动服务..."
    if ! $compose_cmd -f "$file_path" up -d; then
        log_error "服务启动失败"
        log_info "尝试查看 Docker 日志..."
        docker logs "${project_name}-rustdesk" 2>/dev/null | tail -20 || true
        return 1
    fi
    
    # 等待服务启动
    sleep 10
    
    # 设置管理员密码
    log_info "设置管理员密码..."
    for ((i=1; i<=5; i++)); do
        if docker exec "${project_name}-rustdesk" sh -c "./apimain reset-admin-pwd \"$admin_password\"" 2>/dev/null; then
            log_success "管理员密码设置成功"
            return 0
        fi
        log_warning "密码设置失败，重试第 $i 次..."
        sleep 10
    done
    
    log_warning "密码设置失败，请手动执行:"
    log_info "docker exec ${project_name}-rustdesk ./apimain reset-admin-pwd \"YOUR_PASSWORD\""
    return 0
}

# 显示部署信息（简化版，避免颜色问题）
show_deployment_info() {
    local project_name="$1" api_port="$2" hbbs_port="$3" hbbr_port="$4"
    local admin_password="$5"
    
    local ip_info=($(get_ip_address))
    local local_ip="${ip_info[0]}"
    local public_ip="${ip_info[1]}"
    
    echo
    echo "========================================"
    echo "🎉 RustDesk 部署完成！"
    echo "========================================"
    echo
    echo "=== 访问信息 ==="
    echo "Web管理界面: http://${local_ip}:${api_port}"
    if [[ "$public_ip" != "无法获取" ]]; then
        echo "公网访问: http://${public_ip}:${api_port}"
    fi
    echo
    echo "=== 账号信息 ==="
    echo "管理员账号: admin"
    echo "管理员密码: ${admin_password}"
    echo
    echo "=== 密钥信息 ==="
    echo "固定客户端密钥: ${FIXED_KEY_PUB}"
    echo "密钥状态: 已预配置"
    echo
    echo "=== 服务器配置 ==="
    echo "ID 服务器: ${local_ip}:${hbbs_port}"
    echo "中继服务器: ${local_ip}:${hbbr_port}"
    echo "API 服务器: http://${local_ip}:${api_port}"
    echo
    echo "=== 客户端配置步骤 ==="
    echo "1. 打开 RustDesk 客户端"
    echo "2. 点击 ID/中继服务器 设置"
    echo "3. 填写以下信息:"
    echo "   - ID 服务器: ${local_ip}:${hbbs_port}"
    echo "   - 中继服务器: ${local_ip}:${hbbr_port}"
    echo "   - Key: ${FIXED_KEY_PUB}"
    echo "4. 点击 '应用' 保存"
    echo "5. 重启 RustDesk 客户端生效"
    echo
    echo "=== 管理命令 ==="
    echo "查看服务状态: docker ps -f name=${project_name}"
    echo "查看服务日志: docker logs ${project_name}-rustdesk"
    echo "停止服务: cd $SCRIPT_DIR && docker compose down"
    echo "重启服务: cd $SCRIPT_DIR && docker compose restart"
    echo
    echo "=== 重要提示 ==="
    echo "请确保防火墙已开放以下端口:"
    echo "  - API服务端口: ${api_port}"
    echo "  - ID服务器端口: ${hbbs_port}"
    echo "  - 中继服务器端口: ${hbbr_port}"
    echo "  - 其他端口: 21115, 21118, 21119"
    echo
    echo "所有客户端必须使用相同的密钥: ${FIXED_KEY_PUB}"
    echo "此密钥已预配置，客户端连接时无需额外设置"
    echo
}

# 主函数
main() {
    echo
    log_info "开始 RustDesk 服务器部署"
    log_info "使用固定客户端密钥: ${FIXED_KEY_PUB:0:20}..."
    echo "========================================"
    
    # 检查依赖
    local compose_cmd
    compose_cmd=$(check_docker)
    
    # 初始化环境
    create_directories
    
    # 获取配置
    get_user_input
    
    # 设置固定密钥
    setup_fixed_key
    
    # 生成配置文件
    generate_compose_file "$project_name" "$api_port" "$hbbs_port" "$hbbr_port" "$admin_password"
    
    # 部署服务
    if deploy_service "$project_name" "$admin_password" "$compose_cmd"; then
        # 显示部署信息
        show_deployment_info "$project_name" "$api_port" "$hbbs_port" "$hbbr_port" "$admin_password"
        log_success "部署脚本执行完成"
        
        # 显示最终状态
        echo
        log_info "最终状态检查:"
        docker ps -f "name=${project_name}-rustdesk"
    else
        log_error "部署失败，请检查上述错误信息"
        log_info "尝试手动启动: cd $SCRIPT_DIR && $compose_cmd up -d"
        exit 1
    fi
}

# 脚本入口
main "$@"
