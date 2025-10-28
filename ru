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
declare -g SCRIPT_DIR="/data/rustdesk"
declare -g FIXED_KEY_PUB="Doo0qYGYNSEzxoZRPrnV9AtkeX5FFLjcweiH4K1nIJM="
declare -g FIXED_KEY_PRIV=""  # 私钥可以为空，RustDesk公钥模式
declare -g project_name api_port hbbs_port hbbr_port admin_password

# 其他函数保持不变...

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
    
    # 创建空的私钥文件（RustDesk服务器只需要公钥）
    touch "$server_dir/id_ed25519"
    
    # 设置文件权限
    chmod 644 "$server_dir/id_ed25519.pub"
    chmod 600 "$server_dir/id_ed25519"
    
    # 验证密钥文件
    if [[ -f "$server_dir/id_ed25519.pub" ]]; then
        local saved_key=$(cat "$server_dir/id_ed25519.pub")
        if [[ "$saved_key" == "$FIXED_KEY_PUB" ]]; then
            log_success "固定密钥设置成功"
            log_info "客户端密钥: $FIXED_KEY_PUB"
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

# 生成 Docker Compose 配置（使用固定密钥）
generate_compose_file() {
    local project_name="$1" api_port="$2" hbbs_port="$3" hbbr_port="$4"
    local admin_password="$5"
    
    local file_path="$SCRIPT_DIR/docker-compose.yml"
    local ip_info=($(get_ip_address))
    local local_ip="${ip_info[0]}"
    
    # 生成安全的 JWT 密钥
    local jwt_key=$(openssl rand -base64 32 2>/dev/null || 
                   echo "fallback_jwt_key_$(date +%s)$(generate_password)")

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
      # 固定密钥配置 - 使用预生成的密钥文件
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
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

    log_success "Docker Compose 配置文件已生成: $file_path"
}

# 显示部署信息（包含固定密钥）
show_deployment_info() {
    local project_name="$1" api_port="$2" hbbs_port="$3" hbbr_port="$4"
    local admin_password="$5"
    
    local ip_info=($(get_ip_address))
    local local_ip="${ip_info[0]}"
    local public_ip="${ip_info[1]}"
    
    echo
    log_success "🎉 RustDesk 部署完成！"
    echo
    echo "=================== 访问信息 ==================="
    echo -e "Web管理界面: ${GREEN}http://${local_ip}:${api_port}${NC}"
    if [[ "$public_ip" != "无法获取" ]]; then
        echo -e "公网访问: ${GREEN}http://${public_ip}:${api_port}${NC}"
    fi
    echo
    echo "=================== 账号信息 ==================="
    echo -e "管理员账号: ${GREEN}admin${NC}"
    echo -e "管理员密码: ${GREEN}${admin_password}${NC}"
    echo
    echo "=================== 密钥信息 ==================="
    echo -e "固定客户端密钥: ${GREEN}${FIXED_KEY_PUB}${NC}"
    echo -e "密钥状态: ${GREEN}已预配置${NC}"
    echo
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
    echo "   - Key: ${FIXED_KEY_PUB}"
    echo "4. 点击 '应用' 保存"
    echo "5. 重启 RustDesk 客户端生效"
    echo "==================================================="
    echo
    echo "=================== 管理命令 ==================="
    echo -e "查看服务状态: ${YELLOW}docker ps -f name=${project_name}${NC}"
    echo -e "查看服务日志: ${YELLOW}docker logs ${project_name}-rustdesk${NC}"
    echo -e "停止服务: ${YELLOW}cd $SCRIPT_DIR && docker compose down${NC}"
    echo -e "重启服务: ${YELLOW}cd $SCRIPT_DIR && docker compose restart${NC}"
    echo "================================================"
    echo
    log_warning "请确保防火墙已开放以下端口:"
    echo -e "  - API服务端口: ${YELLOW}${api_port}${NC}"
    echo -e "  - ID服务器端口: ${YELLOW}${hbbs_port}${NC}"
    echo -e "  - 中继服务器端口: ${YELLOW}${hbbr_port}${NC}"
    echo -e "  - 其他端口: ${YELLOW}21115, 21118, 21119${NC}"
    
    # 显示重要提示
    echo
    echo "=================== 重要提示 ==================="
    log_info "所有客户端必须使用相同的密钥: ${FIXED_KEY_PUB}"
    log_info "此密钥已预配置，客户端连接时无需额外设置"
    echo "================================================"
}

# 主函数（修改版）
main() {
    echo
    log_info "开始 RustDesk 服务器部署"
    log_info "使用固定客户端密钥: ${FIXED_KEY_PUB:0:20}..."
    echo "========================================"
    
    # 检查依赖
    local compose_cmd=$(check_docker)
    
    # 初始化环境
    create_directories
    
    # 获取配置
    get_user_input
    
    # 设置固定密钥（替换原来的密钥生成）
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
        exit 1
    fi
}

# 脚本入口
main "$@"
