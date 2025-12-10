#!/bin/bash

# 颜色设置
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请以root权限运行此脚本${NC}"
    exit 1
fi

# 检查系统版本
if ! grep -q "Ubuntu\|Debian" /etc/issue; then
    echo -e "${RED}错误：此脚本仅支持Debian和Ubuntu系统${NC}"
    exit 1
fi

# 获取系统信息
echo -e "${YELLOW}正在检查系统信息...${NC}"
sysinfo=$(uname -a)
echo -e "系统信息: $sysinfo"

# 检查当前内核版本
kernel_version=$(uname -r | cut -d- -f1)
echo -e "当前内核版本: $kernel_version"

# 版本号比较函数
version_ge() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

# 检查算法状态
check_algorithm_status() {
    local algorithm=$1
    echo -e "${YELLOW}检查 $algorithm 状态...${NC}"
    
    # 检查算法模块是否已加载
    if [[ "$algorithm" == "bbr" || "$algorithm" == "bbr2" ]]; then
        if ! lsmod | grep -q bbr; then
            echo -e "${RED}$algorithm 模块未加载${NC}"
            return 3
        else
            echo -e "${GREEN}BBR模块已加载${NC}"
        fi
    fi
    
    # 检查算法是否在可用列表中
    sysctl net.ipv4.tcp_available_congestion_control | grep -q $algorithm
    if [ $? -ne 0 ]; then
        echo -e "${RED}$algorithm 不在可用的拥塞控制算法列表中${NC}"
        return 2
    else
        echo -e "${GREEN}$algorithm 在可用的拥塞控制算法列表中${NC}"
    fi
    
    # 检查是否为当前使用的算法
    sysctl net.ipv4.tcp_congestion_control | grep -q $algorithm
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}$algorithm 可用但未被设置为默认算法${NC}"
        return 1
    else
        echo -e "${GREEN}$algorithm 已启用并正在运行${NC}"
        return 0
    fi
}

# 应用选择的算法
apply_algorithm() {
    local algorithm=$1
    local qdisc=$2
    
    echo -e "${YELLOW}正在应用 $algorithm 拥塞控制算法...${NC}"
    
    # 创建配置文件
    cat > /etc/sysctl.d/99-tcp-optimization.conf << EOF
net.core.default_qdisc=$qdisc
net.ipv4.tcp_congestion_control=$algorithm
# 增强网络稳定性的附加配置
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
EOF
    
    # 增加一些额外的稳定性配置
    if [[ "$algorithm" == "bbr" || "$algorithm" == "bbr2" ]]; then
        cat >> /etc/sysctl.d/99-tcp-optimization.conf << EOF
# BBR优化配置
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF
    fi
    
    # 应用配置
    sysctl --system
    
    # 验证配置已应用
    check_algorithm_status $algorithm
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$algorithm 配置成功并已启用${NC}"
    else
        echo -e "${RED}$algorithm 配置失败，请检查系统日志${NC}"
    fi
}

# 显示当前使用的拥塞控制算法
show_current_algorithm() {
    echo -e "${BLUE}当前系统拥塞控制设置:${NC}"
    echo -e "${BLUE}===============================${NC}"
    qdisc=$(sysctl -n net.core.default_qdisc)
    echo -e "当前默认队列算法(qdisc): ${GREEN}$qdisc${NC}"
    
    algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    echo -e "当前拥塞控制算法: ${GREEN}$algo${NC}"
    
    echo -e "${BLUE}可用的拥塞控制算法:${NC}"
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    echo -e "${GREEN}$available${NC}"
    echo
}

# 更新系统
update_system() {
    echo -e "${YELLOW}正在更新系统...${NC}"
    apt update -y
    apt upgrade -y
}

# 选择算法菜单
select_algorithm() {
    show_current_algorithm
    
    echo -e "${BLUE}请选择拥塞控制算法:${NC}"
    echo -e "${BLUE}===============================${NC}"
    echo -e "${GREEN}1)${NC} BBR      - Google的拥塞控制算法，适合大多数场景的平衡选择"
    echo -e "${GREEN}2)${NC} BBR2     - BBR的改进版，更好的公平性和稳定性"
    echo -e "${GREEN}3)${NC} CUBIC    - 默认的Linux拥塞控制算法，连接非常稳定"
    echo -e "${GREEN}4)${NC} Hybla    - 为高延迟网络优化，提高稳定性"
    echo -e "${GREEN}5)${NC} CDG      - 针对低延迟网络，减少缓冲膨胀，稳定连接"
    echo -e "${GREEN}6)${NC} Vegas    - 最早的基于延迟的算法，非常稳定但吞吐量较低"
    echo -e "${GREEN}7)${NC} 退出"
    
    read -p "请输入选择 [1-7]: " choice
    
    case $choice in
        1)
            apply_algorithm "bbr" "fq"
            ;;
        2)
            apply_algorithm "bbr2" "fq"
            ;;
        3)
            apply_algorithm "cubic" "fq"
            ;;
        4)
            apply_algorithm "hybla" "fq"
            ;;
        5)
            apply_algorithm "cdg" "fq_codel"
            ;;
        6)
            apply_algorithm "vegas" "fq"
            ;;
        7)
            echo -e "${YELLOW}退出...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重试${NC}"
            select_algorithm
            ;;
    esac
}

# 检查内核是否支持必要的拥塞控制算法
check_kernel_support() {
    # 检查内核版本是否支持BBR（需要4.9以上）
    if ! version_ge "$kernel_version" "4.9"; then
        echo -e "${YELLOW}当前内核版本 $kernel_version 不支持最新的拥塞控制算法，需要升级内核${NC}"
        
        # 更新系统
        update_system
        
        # 安装必要工具
        echo -e "${YELLOW}安装必要工具...${NC}"
        apt install -y linux-generic linux-image-generic linux-headers-generic
        
        echo -e "${GREEN}内核已更新，请重启系统后再次运行此脚本以启用拥塞控制算法${NC}"
        echo -e "${YELLOW}是否立即重启系统? (y/n)${NC}"
        read -r choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            reboot
        fi
        exit 0
    fi
    
    # 检查支持的算法列表
    echo -e "${YELLOW}检查支持的拥塞控制算法...${NC}"
    local supported_algos=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    echo -e "支持的算法: ${GREEN}$supported_algos${NC}"
    
    # 如果支持的算法少于3个，可能需要加载更多模块
    local count=$(echo "$supported_algos" | wc -w)
    if [ $count -lt 3 ]; then
        echo -e "${YELLOW}尝试加载更多拥塞控制模块...${NC}"
        modprobe tcp_bbr
        modprobe tcp_cubic
        modprobe tcp_hybla
    fi
}

# 为网络稳定性优化一些额外的设置
optimize_network_stability() {
    echo -e "${YELLOW}应用网络稳定性优化...${NC}"
    
    # 创建网络稳定性优化配置
    cat > /etc/sysctl.d/98-network-stability.conf << EOF
# 启用TCP FIN超时保护，防止FIN-WAIT-2状态攻击
net.ipv4.tcp_fin_timeout=15

# 启用TIME-WAIT状态复用，提高连接效率
net.ipv4.tcp_tw_reuse=1

# 减少LAST-ACK状态的连接超时，提高连接释放效率
net.ipv4.tcp_orphan_retries=3

# 增加系统同时打开的文件句柄数
fs.file-max=1000000

# 增加本地端口范围，增加可用连接数
net.ipv4.ip_local_port_range=1024 65535

# 减少TCP保活探测次数，加快检测死连接
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_time=300
EOF
    
    # 应用配置
    sysctl --system
    
    echo -e "${GREEN}网络稳定性优化配置已应用${NC}"
}

# 主函数
main() {
    echo -e "${GREEN}===== Debian/Ubuntu TCP 网络优化脚本 =====${NC}"
    echo -e "${GREEN}===== 重点优化连接稳定性 =====${NC}"
    
    # 检查内核版本和支持
    check_kernel_support
    
    # 优化网络稳定性
    optimize_network_stability
    
    # 显示选择菜单
    select_algorithm
    
    echo -e "${GREEN}===== 网络优化完成 =====${NC}"
    echo -e "${YELLOW}建议：您可能需要重启系统以使所有优化生效${NC}"
}

# 运行主函数
main
