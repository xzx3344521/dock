#!/bin/bash

# 智能APT镜像源配置脚本
# 自动检测地理位置并选择最佳镜像源

set -e  # 遇到错误立即退出

echo "=== 智能APT镜像源配置 ==="

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

# 检测是否在中国大陆
detect_location() {
    log_info "正在检测地理位置..."
    
    # 方法1: 通过IP API检测
    local location_info=""
    if command -v curl &> /dev/null; then
        location_info=$(curl -s --connect-timeout 5 "http://ip-api.com/json/?fields=country,countryCode" || true)
    elif command -v wget &> /dev/null; then
        location_info=$(wget -q -O - --timeout=5 "http://ip-api.com/json/?fields=country,countryCode" || true)
    fi
    
    if [[ -n "$location_info" ]]; then
        if echo "$location_info" | grep -q "China\|CN"; then
            log_success "检测到中国大陆地理位置"
            return 0  # 在中国
        else
            log_info "检测到非中国大陆地理位置"
            return 1  # 不在中国
        fi
    fi
    
    # 方法2: 通过时区检测（备用方案）
    local timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")
    if [[ -n "$timezone" ]]; then
        if [[ "$timezone" == *"Asia/Shanghai"* || "$timezone" == *"Asia/Chongqing"* || "$timezone" == *"Asia/Harbin"* ]]; then
            log_success "通过时区检测到中国大陆"
            return 0
        fi
    fi
    
    # 方法3: 检查系统语言设置
    local lang=$(echo "$LANG" | tr '[:upper:]' '[:lower:]')
    if [[ "$lang" == *"zh_cn"* || "$lang" == *"zh.utf"* ]]; then
        log_success "通过语言设置检测到中国大陆"
        return 0
    fi
    
    log_warning "无法确定地理位置，使用默认配置"
    return 1
}

# 备份原有源列表
backup_sources() {
    if [[ -f /etc/apt/sources.list ]]; then
        local backup_name="/etc/apt/sources.list.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/apt/sources.list "$backup_name"
        log_success "已备份原有源列表: $backup_name"
    fi
}

# 配置国内镜像源（清华源）
setup_china_mirror() {
    log_info "配置清华大学镜像源..."
    
    cat > /etc/apt/sources.list << 'EOF'
# 清华大学 Debian 镜像源
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware

deb https://mirrors.tuna.tsinghua.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware

deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware

deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
EOF

    log_success "清华大学镜像源配置完成"
}

# 配置国外官方源
setup_official_mirror() {
    log_info "配置Debian官方源..."
    
    cat > /etc/apt/sources.list << 'EOF'
# Debian 官方源
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
EOF

    log_success "Debian官方源配置完成"
}

# 测试镜像源速度（可选）
test_mirror_speed() {
    if command -v curl &> /dev/null; then
        log_info "正在测试镜像源连接速度..."
        
        local mirrors=("deb.debian.org" "mirrors.tuna.tsinghua.edu.cn")
        local fastest_mirror=""
        local fastest_time=999
        
        for mirror in "${mirrors[@]}"; do
            local time=$(curl -o /dev/null -s -w "%{time_total}" "https://$mirror" --connect-timeout 3 || echo "999")
            if (( $(echo "$time < $fastest_time" | bc -l) )); then
                fastest_time=$time
                fastest_mirror=$mirror
            fi
            log_info "$mirror: ${time}s"
        done
        
        log_success "最快镜像: $fastest_mirror (${fastest_time}s)"
    fi
}

# 安装开发工具
install_dev_tools() {
    log_info "开始安装开发工具..."
    
    # 更新包列表
    apt update
    
    # 安装基础工具
    local packages=("vim" "build-essential" "g++" "gfortran" "curl" "wget")
    
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            log_info "$pkg 已安装，跳过"
        else
            log_info "安装 $pkg ..."
            apt install -y "$pkg"
        fi
    done
    
    log_success "开发工具安装完成"
}

# 主函数
main() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行此脚本"
        echo "使用方法: sudo $0"
        exit 1
    fi
    
    # 检测系统类型
    if [[ ! -f /etc/debian_version ]]; then
        log_error "此脚本仅适用于Debian/Ubuntu系统"
        exit 1
    fi
    
    # 备份原有配置
    backup_sources
    
    # 检测地理位置并配置相应的镜像源
    if detect_location; then
        setup_china_mirror
    else
        setup_official_mirror
    fi
    
    # 测试镜像速度（可选）
    if command -v bc &> /dev/null; then
        test_mirror_speed
    else
        log_warning "未安装bc，跳过速度测试"
    fi
    
    # 安装开发工具
    install_dev_tools
    
    log_success "=== 配置完成 ==="
    echo ""
    log_info "已安装的工具:"
    echo "  - Vim 编辑器"
    echo "  - GCC/G++ 编译器"
    echo "  - GFortran 编译器"
    echo "  - Build-essential 开发工具包"
    echo "  - curl/wget 网络工具"
}

# 运行主函数
main "$@"
