#!/bin/bash
LIGHT_GREEN='\033[1;32m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
WHITE='\033[1;37m'
CYAN='\033[0;36m'
BOLD='\033[1m'
SUCCESS="${BOLD}${LIGHT_GREEN}"
ADMIN_PASSWORD="Qaz123456!"
VPN_HUB="DEFAULT"
VPN_USER="pi"
VPN_PASSWORD="8888888888!"
DHCP_START="192.168.30.10"
DHCP_END="192.168.30.20"
DHCP_MASK="255.255.255.0"
DHCP_GW="192.168.30.1"
DHCP_DNS1="192.168.30.1"
DHCP_DNS2="8.8.8.8"
FRP_VERSION="v0.62.1"
FRPS_PORT="7000"
FRPS_UDP_PORT="7001"
FRPS_KCP_PORT="7000"
FRPS_DASHBOARD_PORT="31410"
FRPS_TOKEN="DFRN2vbG123"
FRPS_DASHBOARD_USER="admin"
FRPS_DASHBOARD_PWD="yao581581"
SILENT_MODE=true
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

log_info() {

    echo -e "${NC}$1"
}

log_step() {
    echo -e "${NC}$1"
}

log_success() {
    echo -e "${NC}$1"
}

log_error() {
    echo -e "${NC}$1"
    exit 1
}

log_sub_step() {
    echo -e "${NC}$1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 或 root 权限运行脚本"
    fi
}

uninstall_frps() {
    systemctl stop frps >/dev/null 2>&1
    systemctl disable frps >/dev/null 2>&1
    rm -f /etc/systemd/system/frps.service
    rm -rf /usr/local/frp /etc/frp
    systemctl daemon-reload >/dev/null 2>&1
}

install_softether() {
    if [ -d "/usr/local/vpnserver" ]; then
        /usr/local/vpnserver/vpnserver stop >/dev/null 2>&1
        rm -rf /usr/local/vpnserver
    fi
    echo -e "${BLUE}» 下载 SoftEther VPN 服务端...${NC}"
    cd /usr/local/ || { echo -e "${RED}✗ 无法进入 /usr/local/ 目录${NC}"; return 1; }
    echo -e "${CYAN}» 正在下载: softether-vpnserver.tar.gz${NC}" >/dev/null 2>&1
    wget -q "https://www.softether-download.com/files/softether/v4.44-9807-rtm-2025.04.16-tree/Linux/SoftEther_VPN_Server/64bit_-_Intel_x64_or_AMD64/softether-vpnserver-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz" -O "softether-vpnserver.tar.gz" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ SoftEther VPN 下载失败，尝试备用地址...${NC}"
        echo -e "${CYAN}  正在下载备用链接: softether-vpnserver.tar.gz${NC}" >/dev/null 2>&1
        wget -q "https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/v4.38-9760-rtm/softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz" -O "softether-vpnserver.tar.gz" 2>&1 | \
        stdbuf -o0 awk '{ if(match($0, /[0-9]+%/)) printf "\r  下载进度：[%-50s] %s", substr("##################################################", 1, int($0)*50/100), $0; fflush(); }'
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ SoftEther VPN 下载失败，安装中止${NC}"
            return 1
        fi
    fi
    echo -e "${BLUE}» 解压 SoftEther VPN 安装包...${NC}"
    tar -xzf softether-vpnserver.tar.gz
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 解压失败，安装中止${NC}"
        rm -f softether-vpnserver.tar.gz
        return 1
    fi
    echo -e "${BLUE}» 编译 SoftEther VPN...${NC}"
    cd vpnserver || { echo -e "${RED}✗ 无法进入 vpnserver 目录${NC}"; return 1; }
    yes 1 | make -j$(nproc) >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ SoftEther VPN 编译失败${NC}"
        return 1
    fi
    echo -e "${BLUE}» 启动 SoftEther VPN 服务...${NC}"
    chmod +x vpnserver
    ./vpnserver start >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ SoftEther VPN 服务启动失败${NC}"
        return 1
    fi
    sleep 1
    echo -e "${BLUE}» 配置 SoftEther VPN...${NC}"
    configure_vpn
    echo -e "${BLUE}» 创建系统服务...${NC}"
    create_vpn_service
    return 0
}

configure_vpn() {
    echo -e "${CYAN}  ├─ 配置 VPN 服务器管理密码...${NC}"
    local VPNCMD="/usr/local/vpnserver/vpncmd"
    ${VPNCMD} localhost /SERVER /CMD ServerPasswordSet ${ADMIN_PASSWORD} >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 创建虚拟 Hub...${NC}"
    ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD HubDelete ${VPN_HUB} >/dev/null 2>&1 || true
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD HubCreate ${VPN_HUB} /PASSWORD:${ADMIN_PASSWORD} >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 配置加密套件...${NC}"
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD ServerCipherSet ECDHE-RSA-AES256-GCM-SHA384 >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 启用安全 NAT...${NC}"
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD SecureNatEnable >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 配置 DHCP 设置...${NC}"
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD DhcpSet \
        /START:${DHCP_START} /END:${DHCP_END} /MASK:${DHCP_MASK} /EXPIRE:2000000 \
        /GW:${DHCP_GW} /DNS:${DHCP_DNS1} /DNS2:${DHCP_DNS2} /DOMAIN:none /LOG:no >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 创建 VPN 用户...${NC}"
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} \
        /CMD UserCreate ${VPN_USER} /GROUP:none /REALNAME:none /NOTE:none >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 设置用户密码...${NC}"
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} \
        /CMD UserPasswordSet ${VPN_USER} /PASSWORD:${VPN_PASSWORD} >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 优化日志设置...${NC}"
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable packet >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable security >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable server >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable bridge >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable connection >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD LogDisable >/dev/null 2>&1
    echo -e "${CYAN}  ├─ 配置服务端口...${NC}"
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD OpenVpnEnable false /PORTS:1194 >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD SstpEnable false >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD UdpAccelerationSet false >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD ListenerDelete 992 >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD ListenerDelete 1194 >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD ListenerDelete 5555 >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD ListenerCreate 443 >/dev/null 2>&1
}

create_vpn_service() {
    echo -e "${CYAN}  ├─ 创建系统服务单元...${NC}"
    cat > /etc/systemd/system/vpn.service <<EOF
[Unit]
Description=SoftEther VPN Server
After=network.target
[Service]
Type=forking
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStop=/usr/local/vpnserver/vpnserver stop
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    echo -e "${CYAN}  ├─ 重载 systemd 配置...${NC}"
    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${CYAN}  └─ 启用并启动 VPN 服务...${NC}"
    systemctl enable --now vpn >/dev/null 2>&1
    sleep 2
    if systemctl is-active vpn >/dev/null 2>&1; then
    echo -e "${CYAN}  └─ SoftEther VPN服务已成功启动...${NC}"
    fi
}

install_frps() {
    uninstall_frps
    echo -e "${BLUE}» 下载 FRPS 服务端...${NC}"
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || {
        echo -e "${RED}✗ 无法进入 /usr/local/ 目录${NC}"
        return 1
    }
    echo -e "${CYAN}  正在下载: ${FRP_FILE}${NC}" >/dev/null 2>&1
    wget -q "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ FRP 下载失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 解压 FRPS 安装包...${NC}"
    if ! tar -zxf "${FRP_FILE}"; then
        echo -e "${RED}✗ FRP 解压失败！${NC}"
        rm -f "${FRP_FILE}"
        return 1
    fi
    echo -e "${BLUE}» 安装 FRPS 可执行文件...${NC}"
    cd "${FRP_NAME}" 
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法进入 FRP 目录！${NC}"
        return 1
    fi
    rm -f frpc*
    mkdir -p /usr/local/frp
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 创建 /usr/local/frp 目录失败！${NC}"
        return 1
    fi
    if ! cp frps /usr/local/frp/; then
        echo -e "${RED}✗ 拷贝 frps 可执行文件失败！${NC}"
        return 1
    fi
    chmod +x /usr/local/frp/frps
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 设置 frps 可执行权限失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 创建 FRPS 配置文件...${NC}"
    mkdir -p /etc/frp
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 创建 /etc/frp 目录失败！${NC}"
        return 1
    fi
    cat > /etc/frp/frps.toml << EOF
bindAddr = "0.0.0.0"
bindPort = ${FRPS_PORT}
kcpBindPort = ${FRPS_KCP_PORT}
auth.method = "token"
auth.token = "${FRPS_TOKEN}"
webServer.addr = "0.0.0.0"
webServer.port = ${FRPS_DASHBOARD_PORT}
webServer.user = "${FRPS_DASHBOARD_USER}"
webServer.password = "${FRPS_DASHBOARD_PWD}"
enablePrometheus = true
log.level = "error"
log.to = "none"
EOF
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 写入 frps.toml 配置文件失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 创建 FRPS 服务单元...${NC}"
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/frp/frps -c /etc/frp/frps.toml
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
EOF
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 写入 frps.service 文件失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 配置防火墙规则...${NC}"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow ${FRPS_PORT}/tcp >/dev/null 2>&1
        ufw allow ${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
        echo -e "${CYAN}  └─ 已添加 UFW 防火墙规则${NC}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${FRPS_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "${CYAN}  └─ 已添加 firewalld 防火墙规则${NC}"
    fi
    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 重新加载 systemd 配置失败！${NC}"
        return 1
    fi
    systemctl enable frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 启用 frps 服务失败！${NC}"
        return 1
    fi
        echo -e "${CYAN}  └─ 启用并启动 FRPS 服务...${NC}"
    systemctl start frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 启动 frps 服务失败！${NC}"
        journalctl -u frps.service --no-pager -n 20
        return 1
    fi
    if systemctl is-active frps >/dev/null 2>&1; then
      echo -e "${CYAN}  └─ FRPS 服务已成功启动...${NC}"
    else
        echo -e "${RED}✗ FRPS服务启动失败${NC}"
        return 1
    fi
    rm -f /usr/local/${FRP_FILE}
    rm -rf /usr/local/${FRP_NAME}
}

add_cron_job() {
    local cron_entry='24 15 24 * * find /usr/local -type f -name "*.log" -delete'
    (crontab -l 2>/dev/null | grep -v -F "$cron_entry") | crontab -
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -

}

cleanup() {
    rm -rf /usr/local/frp_* /usr/local/softether-vpnserver-v4* /usr/local/frp_*_linux_amd64
    rm -rf /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log
}

uninstall_all() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               卸载所有服务                      ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}» 停止并卸载 VPN 服务...${NC}"
    systemctl stop vpn >/dev/null 2>&1
    systemctl disable vpn >/dev/null 2>&1
    rm -f /etc/systemd/system/vpn.service
    echo -e "${BLUE}» 清理 VPN 服务文件...${NC}"
    rm -rf /usr/local/vpnserver
    pkill -9 vpnserver 2>/dev/null || true
    pkill -9 vpncmd 2>/dev/null || true
    echo -e "${BLUE}» 卸载 FRPS 服务...${NC}"
    uninstall_frps
    echo -e "${BLUE}» 清理临时文件...${NC}"
    cleanup 
    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${SUCCESS}✓ 所有服务已成功卸载。${NC}"
    sleep 2
}

show_results() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               服务信息摘要                      ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}${BOLD}▎ FRPS 服务信息${NC}"
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    local frps_status=$(systemctl status frps --no-pager | grep -E 'Active:' | sed 's/^\s*Active: //g')
    echo -e "  ${BOLD}• 服务状态:${NC}   ${WHITE}${frps_status}${NC}"
    echo -e "  ${BOLD}• 服务器地址:${NC}   ${WHITE}${SERVER_IP}${NC}"
    echo -e "  ${BOLD}• FRPS 端口:${NC}    ${WHITE}${FRPS_PORT}${NC}"
    echo -e "  ${BOLD}• FRPS 令牌:${NC}    ${WHITE}${FRPS_TOKEN}${NC}"
    echo -e "  ${BOLD}• Web 管理界面:${NC} ${WHITE}http://${SERVER_IP}:${FRPS_DASHBOARD_PORT}${NC}"
    if systemctl is-active vpn >/dev/null 2>&1; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${WHITE}${BOLD}▎ SoftEtherVPN 服务信息${NC}"
        local vpn_status=$(systemctl status vpn --no-pager | grep -E 'Active:' | sed 's/^\s*Active: //g')
        echo -e "  ${BOLD}• 服务状态:${NC}   ${WHITE}${vpn_status}${NC}"
        echo -e "  ${BOLD}• 服务器地址:${NC} ${WHITE}${SERVER_IP}${NC}"
        echo -e "  ${BOLD}• VPN Hub:${NC}    ${WHITE}${VPN_HUB}${NC}"
        echo -e "  ${BOLD}• VPN 用户名:${NC} ${WHITE}${VPN_USER}${NC}"
        echo -e "  ${BOLD}• VPN 密码:${NC}   ${WHITE}${VPN_PASSWORD}${NC}"
        echo -e "  ${BOLD}• 管理密码:${NC}   ${WHITE}${ADMIN_PASSWORD}${NC}"
    fi
}

install_frp_only() {
    check_root
    uninstall_frps
    install_frps
    echo -e "${SUCCESS}✓ FRPS服务安装并启动成功！${NC}"
    show_results
    sleep 2
    exit 0
}

install_softether_and_frps() {
    check_root
    systemctl stop vpn >/dev/null 2>&1
    systemctl disable vpn >/dev/null 2>&1
    rm -f /etc/systemd/system/vpn.service
    rm -rf /usr/local/vpnserver
    pkill -9 vpnserver 2>/dev/null || true
    pkill -9 vpncmd 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1
    uninstall_frps
    echo -e "${BLUE}» 安装 SoftEther VPN...${NC}"
    if ! install_softether; then
        echo -e "${RED}✗ SoftEther VPN 安装失败，继续安装 FRPS...${NC}"
    fi
    echo -e "${BLUE}» 安装 FRPS 服务...${NC}"
    install_frps
    echo -e "${BLUE}» 添加清理定时任务...${NC}"
    add_cron_job
    echo -e "${BLUE}» 清理临时文件...${NC}"
    cleanup
    echo -e "${SUCCESS}✓ SoftEtherVPN 和 FRPS 安装完成${NC}"
    show_results
    exit 0
}

show_menu() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               Pi Network 管理面板              ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo -e "${LIGHT_GREEN}请选择要执行的操作:${NC}"
    echo -e "  ${BLUE}1)${NC} 安装 SoftEtherVPN和FRPS服务"
    echo -e "  ${BLUE}2)${NC} 卸载所有服务" 
    echo -e "  ${BLUE}3)${NC} 退出脚本"
    echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"
    echo -n "请输入选项 [1-3]: "
    read -r choice
    case "$choice" in
        1)
            check_root
            install_softether_and_frps
            exit 0
            ;;
        2)
            check_root
            uninstall_all
            ;;
        3)
            echo -e "${GREEN}退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1-3 之间的数字。${NC}"
            ;;
    esac
}

main() {
    while true; do
        clear
        show_menu
    done
}

main
