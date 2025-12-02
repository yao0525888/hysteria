#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请以root权限运行此脚本${NC}"
    exit 1
fi

if ! grep -q "Ubuntu\|Debian" /etc/issue; then
    echo -e "${RED}错误：此脚本仅支持Debian和Ubuntu系统${NC}"
    exit 1
fi

echo -e "${YELLOW}正在检查系统信息...${NC}"
sysinfo=$(uname -a)
echo -e "系统信息: $sysinfo"

kernel_version=$(uname -r | cut -d- -f1)
echo -e "当前内核版本: $kernel_version"

version_ge() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

check_algorithm_status() {
    local algorithm=$1
    echo -e "${YELLOW}检查 $algorithm 状态...${NC}"
    
    if [[ "$algorithm" == "bbr" || "$algorithm" == "bbr2" ]]; then
        if ! lsmod | grep -q bbr; then
            echo -e "${RED}$algorithm 模块未加载${NC}"
            return 3
        else
            echo -e "${GREEN}BBR模块已加载${NC}"
        fi
    fi
    
    sysctl net.ipv4.tcp_available_congestion_control | grep -q $algorithm
    if [ $? -ne 0 ]; then
        echo -e "${RED}$algorithm 不在可用的拥塞控制算法列表中${NC}"
        return 2
    else
        echo -e "${GREEN}$algorithm 在可用的拥塞控制算法列表中${NC}"
    fi
    
    sysctl net.ipv4.tcp_congestion_control | grep -q $algorithm
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}$algorithm 可用但未被设置为默认算法${NC}"
        return 1
    else
        echo -e "${GREEN}$algorithm 已启用并正在运行${NC}"
        return 0
    fi
}

apply_algorithm() {
    local algorithm=$1
    local qdisc=$2
    
    echo -e "${YELLOW}正在应用 $algorithm 拥塞控制算法...${NC}"
    
    cat > /etc/sysctl.d/99-tcp-optimization.conf << EOF
net.core.default_qdisc=$qdisc
net.ipv4.tcp_congestion_control=$algorithm
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
EOF
    
    if [[ "$algorithm" == "bbr" || "$algorithm" == "bbr2" ]]; then
        cat >> /etc/sysctl.d/99-tcp-optimization.conf << EOF
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF
    fi
    
    sysctl --system
    
    check_algorithm_status $algorithm
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$algorithm 配置成功并已启用${NC}"
    else
        echo -e "${RED}$algorithm 配置失败，请检查系统日志${NC}"
    fi
}

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

update_system() {
    echo -e "${YELLOW}正在更新系统...${NC}"
    apt update -y
    apt upgrade -y
}

select_algorithm() {
    show_current_algorithm
    echo -e "${BLUE}本脚本已简化为仅应用 Hybla 拥塞控制算法${NC}"
    echo -e "${BLUE}为高延迟网络优化，提高连接稳定性...${NC}"
    apply_algorithm "hybla" "fq"
}

check_kernel_support() {
    if ! version_ge "$kernel_version" "4.9"; then
        echo -e "${YELLOW}当前内核版本 $kernel_version 不支持最新的拥塞控制算法，需要升级内核${NC}"
        
        update_system
        
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
    
    echo -e "${YELLOW}检查支持的拥塞控制算法...${NC}"
    local supported_algos=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    echo -e "支持的算法: ${GREEN}$supported_algos${NC}"
    
    local count=$(echo "$supported_algos" | wc -w)
    if [ $count -lt 3 ]; then
        echo -e "${YELLOW}尝试加载更多拥塞控制模块...${NC}"
        modprobe tcp_bbr
        modprobe tcp_cubic
        modprobe tcp_hybla
    fi
}

optimize_network_stability() {
    echo -e "${YELLOW}应用网络稳定性优化...${NC}"
    
    cat > /etc/sysctl.d/98-network-stability.conf << EOF
    net.ipv4.tcp_fin_timeout=15
    net.ipv4.tcp_tw_reuse=1
    net.ipv4.tcp_orphan_retries=3
    fs.file-max=1000000
    net.ipv4.ip_local_port_range=1024 65535
    net.ipv4.tcp_keepalive_probes=5
    net.ipv4.tcp_keepalive_intvl=15
    net.ipv4.tcp_keepalive_time=300
EOF
    
    sysctl --system
    
    echo -e "${GREEN}网络稳定性优化配置已应用${NC}"
}

main() {
    echo -e "${GREEN}===== Debian/Ubuntu TCP 网络优化脚本 =====${NC}"
    echo -e "${GREEN}===== 重点优化连接稳定性 =====${NC}"
    
    check_kernel_support
    optimize_network_stability
    select_algorithm
    
    echo -e "${GREEN}===== 网络优化完成 =====${NC}"
    echo -e "${YELLOW}建议：您可能需要重启系统以使所有优化生效${NC}"
}

main
