#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以root权限运行"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统类型"
        exit 1
    fi
    
    print_info "检测到操作系统: $OS $VERSION"
}

get_public_ip() {
    PUBLIC_IP=$(curl -s http://ifconfig.me || curl -s http://ipinfo.io/ip || curl -s http://icanhazip.com)
    if [[ -z "$PUBLIC_IP" ]]; then
        print_error "无法获取公网IP地址"
        exit 1
    fi
    print_info "服务器公网IP: $PUBLIC_IP"
}

generate_psk() {
    PSK=$(openssl rand -base64 32)
}

get_user_input() {
    echo ""
    echo "=========================================="
    echo "    L2TP/IPsec VPN 配置向导"
    echo "=========================================="
    echo ""
    
    read -p "请输入VPN用户名 [默认: vpnuser]: " VPN_USER
    VPN_USER=${VPN_USER:-vpnuser}
    
    read -s -p "请输入VPN密码 [默认: 随机生成]: " VPN_PASSWORD
    echo ""
    if [[ -z "$VPN_PASSWORD" ]]; then
        VPN_PASSWORD=$(openssl rand -base64 16)
        print_info "已生成随机密码"
    fi
    
    read -p "是否使用自定义IPsec PSK预共享密钥? (y/n) [默认: n]: " CUSTOM_PSK
    if [[ "$CUSTOM_PSK" == "y" || "$CUSTOM_PSK" == "Y" ]]; then
        read -s -p "请输入PSK预共享密钥: " PSK
        echo ""
    else
        generate_psk
        print_info "已生成随机PSK"
    fi
    
    read -p "VPN客户端IP池起始地址 [默认: 10.10.10.10]: " IP_RANGE_START
    IP_RANGE_START=${IP_RANGE_START:-10.10.10.10}
    
    read -p "VPN客户端IP池结束地址 [默认: 10.10.10.100]: " IP_RANGE_END
    IP_RANGE_END=${IP_RANGE_END:-10.10.10.100}
    
    read -p "本地IP地址 [默认: 10.10.10.1]: " LOCAL_IP
    LOCAL_IP=${LOCAL_IP:-10.10.10.1}
    
    echo ""
    print_info "配置信息已设置完成"
}

install_packages_debian() {
    print_info "更新软件包列表..."
    apt-get update -y
    
    print_info "安装必要的软件包..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        strongswan \
        strongswan-pki \
        libstrongswan-extra-plugins \
        libcharon-extra-plugins \
        xl2tpd \
        net-tools \
        iptables \
        iptables-persistent
}

install_packages_centos() {
    print_info "安装EPEL源..."
    yum install -y epel-release || dnf install -y epel-release
    
    print_info "安装必要的软件包..."
    if command -v dnf &> /dev/null; then
        dnf install -y strongswan xl2tpd iptables iptables-services
    else
        yum install -y strongswan xl2tpd iptables iptables-services
    fi
}

configure_ipsec() {
    print_info "配置IPsec..."
    
    cat > /etc/ipsec.conf <<EOF
config setup
    charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"
    uniqueids=never

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev1
    authby=secret
    ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,aes128-sha1,3des-sha1!

conn L2TP-PSK
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    auto=add
EOF

    cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "$PSK"
EOF

    chmod 600 /etc/ipsec.secrets
}

configure_xl2tpd() {
    print_info "配置xl2tpd..."
    
    cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
auth file = /etc/ppp/chap-secrets

[lns default]
ip range = $IP_RANGE_START-$IP_RANGE_END
local ip = $LOCAL_IP
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd <<EOF
+mschap-v2
ipcp-accept-local
ipcp-accept-remote
noccp
auth
mtu 1410
mru 1410
nodefaultroute
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
connect-delay 5000
ms-dns 8.8.8.8
ms-dns 8.8.4.4
EOF

    cat > /etc/ppp/chap-secrets <<EOF
$VPN_USER       l2tpd   $VPN_PASSWORD           *
EOF

    chmod 600 /etc/ppp/chap-secrets
}

configure_sysctl() {
    print_info "配置系统内核参数..."
    
    cat >> /etc/sysctl.conf <<EOF

net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF

    sysctl -p
}

configure_firewall() {
    print_info "配置防火墙规则..."
    
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    iptables -I INPUT -p udp --dport 500 -j ACCEPT
    iptables -I INPUT -p udp --dport 4500 -j ACCEPT
    iptables -I INPUT -p udp --dport 1701 -j ACCEPT
    iptables -I INPUT -p esp -j ACCEPT
    
    iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $DEFAULT_IFACE -j MASQUERADE
    iptables -A FORWARD -s 10.10.10.0/24 -j ACCEPT
    iptables -A FORWARD -d 10.10.10.0/24 -j ACCEPT
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        netfilter-persistent save
        netfilter-persistent reload
    elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
        service iptables save
    fi
    
    print_info "防火墙规则已配置"
}

start_services() {
    print_info "启动VPN服务..."
    
    systemctl restart strongswan 2>/dev/null || systemctl restart ipsec
    systemctl enable strongswan 2>/dev/null || systemctl enable ipsec
    
    systemctl restart xl2tpd
    systemctl enable xl2tpd
    
    sleep 2
    
    if systemctl is-active --quiet strongswan || systemctl is-active --quiet ipsec; then
        print_info "IPsec服务已启动"
    else
        print_warning "IPsec服务启动失败，请检查配置"
    fi
    
    if systemctl is-active --quiet xl2tpd; then
        print_info "xl2tpd服务已启动"
    else
        print_warning "xl2tpd服务启动失败，请检查配置"
    fi
}

show_config() {
    echo ""
    echo "=========================================="
    echo "    VPN配置完成！"
    echo "=========================================="
    echo ""
    echo -e "${GREEN}服务器IP:${NC}        $PUBLIC_IP"
    echo -e "${GREEN}IPsec PSK:${NC}       $PSK"
    echo -e "${GREEN}VPN用户名:${NC}       $VPN_USER"
    echo -e "${GREEN}VPN密码:${NC}         $VPN_PASSWORD"
    echo ""
    echo "=========================================="
    echo "客户端配置说明:"
    echo "=========================================="
    echo "1. Windows客户端:"
    echo "   - 控制面板 -> 网络和共享中心 -> 设置新的连接或网络"
    echo "   - 选择 '连接到工作区' -> '使用我的Internet连接(VPN)'"
    echo "   - Internet地址: $PUBLIC_IP"
    echo "   - 连接类型: L2TP/IPsec"
    echo "   - 预共享密钥: $PSK"
    echo ""
    echo "2. macOS客户端:"
    echo "   - 系统偏好设置 -> 网络 -> '+' -> VPN(L2TP over IPsec)"
    echo "   - 服务器地址: $PUBLIC_IP"
    echo "   - 账户名称: $VPN_USER"
    echo "   - 密码: $VPN_PASSWORD"
    echo "   - 机密: $PSK"
    echo ""
    echo "3. iOS/Android客户端:"
    echo "   - 设置 -> VPN -> 添加VPN配置"
    echo "   - 类型: L2TP"
    echo "   - 服务器: $PUBLIC_IP"
    echo "   - 用户名: $VPN_USER"
    echo "   - 密码: $VPN_PASSWORD"
    echo "   - 密钥: $PSK"
    echo "=========================================="
    echo ""
    
    cat > /root/vpn_config.txt <<EOF
L2TP/IPsec VPN 配置信息
生成时间: $(date)

服务器IP: $PUBLIC_IP
IPsec PSK: $PSK
VPN用户名: $VPN_USER
VPN密码: $VPN_PASSWORD
IP池范围: $IP_RANGE_START - $IP_RANGE_END
本地IP: $LOCAL_IP
EOF
    
    print_info "配置信息已保存到 /root/vpn_config.txt"
}

add_vpn_user() {
    read -p "请输入新用户名: " NEW_USER
    if grep -q "^$NEW_USER[[:space:]]" /etc/ppp/chap-secrets 2>/dev/null; then
        print_error "用户 $NEW_USER 已存在"
        return 1
    fi
    read -s -p "请输入新密码: " NEW_PASSWORD
    echo ""
    
    echo "$NEW_USER       l2tpd   $NEW_PASSWORD           *" >> /etc/ppp/chap-secrets
    print_info "用户 $NEW_USER 已添加"
    
    systemctl restart xl2tpd
}

delete_vpn_user() {
    if [[ ! -f /etc/ppp/chap-secrets ]]; then
        print_error "配置文件不存在"
        return 1
    fi
    
    echo ""
    echo "当前VPN用户列表:"
    echo "----------------------------------------"
    awk '{if(NF>=3 && $1!~/#/) print "  - " $1}' /etc/ppp/chap-secrets
    echo "----------------------------------------"
    echo ""
    
    read -p "请输入要删除的用户名: " DEL_USER
    if ! grep -q "^$DEL_USER[[:space:]]" /etc/ppp/chap-secrets; then
        print_error "用户 $DEL_USER 不存在"
        return 1
    fi
    
    read -p "确认删除用户 $DEL_USER? (y/n): " CONFIRM
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        sed -i "/^$DEL_USER[[:space:]]/d" /etc/ppp/chap-secrets
        print_info "用户 $DEL_USER 已删除"
        systemctl restart xl2tpd
    else
        print_warning "已取消删除操作"
    fi
}

modify_vpn_password() {
    if [[ ! -f /etc/ppp/chap-secrets ]]; then
        print_error "配置文件不存在"
        return 1
    fi
    
    echo ""
    echo "当前VPN用户列表:"
    echo "----------------------------------------"
    awk '{if(NF>=3 && $1!~/#/) print "  - " $1}' /etc/ppp/chap-secrets
    echo "----------------------------------------"
    echo ""
    
    read -p "请输入要修改密码的用户名: " MOD_USER
    if ! grep -q "^$MOD_USER[[:space:]]" /etc/ppp/chap-secrets; then
        print_error "用户 $MOD_USER 不存在"
        return 1
    fi
    
    read -s -p "请输入新密码: " NEW_PASS
    echo ""
    read -s -p "请再次输入新密码: " NEW_PASS2
    echo ""
    
    if [[ "$NEW_PASS" != "$NEW_PASS2" ]]; then
        print_error "两次输入的密码不一致"
        return 1
    fi
    
    sed -i "s/^$MOD_USER[[:space:]].*/$MOD_USER       l2tpd   $NEW_PASS           */" /etc/ppp/chap-secrets
    print_info "用户 $MOD_USER 的密码已修改"
    systemctl restart xl2tpd
}

list_vpn_users() {
    if [[ ! -f /etc/ppp/chap-secrets ]]; then
        print_error "配置文件不存在"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "        VPN用户列表"
    echo "=========================================="
    awk '{if(NF>=3 && $1!~/#/) printf "  用户名: %-20s 密码: %s\n", $1, $3}' /etc/ppp/chap-secrets
    echo "=========================================="
    echo ""
}

show_current_config() {
    echo ""
    echo "=========================================="
    echo "        当前VPN配置"
    echo "=========================================="
    
    PUBLIC_IP=$(curl -s http://ifconfig.me || curl -s http://ipinfo.io/ip || echo "无法获取")
    echo -e "${GREEN}服务器IP:${NC}        $PUBLIC_IP"
    
    if [[ -f /etc/ipsec.secrets ]]; then
        PSK=$(grep "PSK" /etc/ipsec.secrets | awk -F'"' '{print $2}')
        echo -e "${GREEN}IPsec PSK:${NC}       $PSK"
    fi
    
    if [[ -f /etc/xl2tpd/xl2tpd.conf ]]; then
        IP_RANGE=$(grep "ip range" /etc/xl2tpd/xl2tpd.conf | awk '{print $3}')
        LOCAL_IP=$(grep "local ip" /etc/xl2tpd/xl2tpd.conf | awk '{print $3}')
        echo -e "${GREEN}IP池范围:${NC}        $IP_RANGE"
        echo -e "${GREEN}本地IP:${NC}          $LOCAL_IP"
    fi
    
    echo ""
    echo "服务状态:"
    if systemctl is-active --quiet strongswan || systemctl is-active --quiet ipsec; then
        echo -e "  IPsec:    ${GREEN}运行中${NC}"
    else
        echo -e "  IPsec:    ${RED}已停止${NC}"
    fi
    
    if systemctl is-active --quiet xl2tpd; then
        echo -e "  xl2tpd:   ${GREEN}运行中${NC}"
    else
        echo -e "  xl2tpd:   ${RED}已停止${NC}"
    fi
    
    echo "=========================================="
    echo ""
}

modify_psk() {
    if [[ ! -f /etc/ipsec.secrets ]]; then
        print_error "IPsec配置文件不存在"
        return 1
    fi
    
    read -p "是否自动生成新的PSK? (y/n): " AUTO_PSK
    if [[ "$AUTO_PSK" == "y" || "$AUTO_PSK" == "Y" ]]; then
        NEW_PSK=$(openssl rand -base64 32)
    else
        read -s -p "请输入新的PSK: " NEW_PSK
        echo ""
    fi
    
    cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "$NEW_PSK"
EOF
    
    chmod 600 /etc/ipsec.secrets
    print_info "PSK已更新: $NEW_PSK"
    
    systemctl restart strongswan 2>/dev/null || systemctl restart ipsec
    print_info "IPsec服务已重启"
}

modify_l2tp_config() {
    if [[ ! -f /etc/xl2tpd/xl2tpd.conf ]]; then
        print_error "L2TP配置文件不存在"
        return 1
    fi
    
    CURRENT_IP_RANGE=$(grep "ip range" /etc/xl2tpd/xl2tpd.conf | awk '{print $3}')
    CURRENT_LOCAL_IP=$(grep "local ip" /etc/xl2tpd/xl2tpd.conf | awk '{print $3}')
    
    echo ""
    echo "=========================================="
    echo "        修改L2TP配置"
    echo "=========================================="
    echo ""
    echo "当前配置:"
    echo "  IP池范围: $CURRENT_IP_RANGE"
    echo "  本地IP:   $CURRENT_LOCAL_IP"
    echo ""
    
    read -p "新的IP池起始地址 [回车保持不变]: " NEW_IP_START
    read -p "新的IP池结束地址 [回车保持不变]: " NEW_IP_END
    read -p "新的本地IP地址 [回车保持不变]: " NEW_LOCAL_IP
    
    if [[ -n "$NEW_IP_START" && -n "$NEW_IP_END" ]]; then
        sed -i "s|ip range = .*|ip range = $NEW_IP_START-$NEW_IP_END|" /etc/xl2tpd/xl2tpd.conf
        print_info "IP池范围已更新为: $NEW_IP_START-$NEW_IP_END"
    fi
    
    if [[ -n "$NEW_LOCAL_IP" ]]; then
        sed -i "s|local ip = .*|local ip = $NEW_LOCAL_IP|" /etc/xl2tpd/xl2tpd.conf
        print_info "本地IP已更新为: $NEW_LOCAL_IP"
    fi
    
    if [[ -n "$NEW_IP_START" || -n "$NEW_LOCAL_IP" ]]; then
        systemctl restart xl2tpd
        print_info "L2TP服务已重启"
    else
        print_warning "未进行任何修改"
    fi
}

modify_dns() {
    if [[ ! -f /etc/ppp/options.xl2tpd ]]; then
        print_error "PPP配置文件不存在"
        return 1
    fi
    
    CURRENT_DNS1=$(grep "ms-dns" /etc/ppp/options.xl2tpd | head -n1 | awk '{print $2}')
    CURRENT_DNS2=$(grep "ms-dns" /etc/ppp/options.xl2tpd | tail -n1 | awk '{print $2}')
    
    echo ""
    echo "=========================================="
    echo "        修改DNS服务器"
    echo "=========================================="
    echo ""
    echo "当前DNS服务器:"
    echo "  主DNS: $CURRENT_DNS1"
    echo "  备DNS: $CURRENT_DNS2"
    echo ""
    echo "常用DNS服务器:"
    echo "  1. Google DNS (8.8.8.8 / 8.8.4.4)"
    echo "  2. Cloudflare (1.1.1.1 / 1.0.0.1)"
    echo "  3. 阿里DNS (223.5.5.5 / 223.6.6.6)"
    echo "  4. 腾讯DNS (119.29.29.29 / 182.254.116.116)"
    echo "  5. 自定义"
    echo ""
    
    read -p "请选择 [1-5]: " DNS_CHOICE
    
    case $DNS_CHOICE in
        1)
            DNS1="8.8.8.8"
            DNS2="8.8.4.4"
            ;;
        2)
            DNS1="1.1.1.1"
            DNS2="1.0.0.1"
            ;;
        3)
            DNS1="223.5.5.5"
            DNS2="223.6.6.6"
            ;;
        4)
            DNS1="119.29.29.29"
            DNS2="182.254.116.116"
            ;;
        5)
            read -p "请输入主DNS: " DNS1
            read -p "请输入备DNS: " DNS2
            ;;
        *)
            print_error "无效的选择"
            return 1
            ;;
    esac
    
    sed -i "s/ms-dns .*/ms-dns $DNS1/" /etc/ppp/options.xl2tpd
    sed -i "s/ms-dns $DNS1/ms-dns $DNS1\nms-dns $DNS2/" /etc/ppp/options.xl2tpd
    
    grep -v "ms-dns" /etc/ppp/options.xl2tpd > /tmp/options.xl2tpd.tmp
    cat /tmp/options.xl2tpd.tmp > /etc/ppp/options.xl2tpd
    echo "ms-dns $DNS1" >> /etc/ppp/options.xl2tpd
    echo "ms-dns $DNS2" >> /etc/ppp/options.xl2tpd
    rm -f /tmp/options.xl2tpd.tmp
    
    print_info "DNS服务器已更新为: $DNS1 / $DNS2"
    systemctl restart xl2tpd
    print_info "L2TP服务已重启"
}

modify_mtu() {
    if [[ ! -f /etc/ppp/options.xl2tpd ]]; then
        print_error "PPP配置文件不存在"
        return 1
    fi
    
    CURRENT_MTU=$(grep "^mtu" /etc/ppp/options.xl2tpd | awk '{print $2}')
    CURRENT_MRU=$(grep "^mru" /etc/ppp/options.xl2tpd | awk '{print $2}')
    
    echo ""
    echo "当前MTU/MRU值: $CURRENT_MTU / $CURRENT_MRU"
    echo ""
    read -p "请输入新的MTU值 [默认: 1410]: " NEW_MTU
    NEW_MTU=${NEW_MTU:-1410}
    
    read -p "请输入新的MRU值 [默认: $NEW_MTU]: " NEW_MRU
    NEW_MRU=${NEW_MRU:-$NEW_MTU}
    
    sed -i "s/^mtu .*/mtu $NEW_MTU/" /etc/ppp/options.xl2tpd
    sed -i "s/^mru .*/mru $NEW_MRU/" /etc/ppp/options.xl2tpd
    
    print_info "MTU/MRU已更新为: $NEW_MTU / $NEW_MRU"
    systemctl restart xl2tpd
    print_info "L2TP服务已重启"
}

show_vpn_status() {
    echo ""
    echo "=========================================="
    echo "        VPN服务状态"
    echo "=========================================="
    echo ""
    
    echo "【IPsec服务状态】"
    systemctl status strongswan 2>/dev/null || systemctl status ipsec
    echo ""
    
    echo "【xl2tpd服务状态】"
    systemctl status xl2tpd
    echo ""
    
    echo "【当前连接】"
    if command -v ipsec &> /dev/null; then
        ipsec statusall 2>/dev/null || echo "无活动连接"
    fi
    echo ""
}

restart_vpn_services() {
    print_info "正在重启VPN服务..."
    
    systemctl restart strongswan 2>/dev/null || systemctl restart ipsec
    systemctl restart xl2tpd
    
    sleep 2
    
    if systemctl is-active --quiet strongswan || systemctl is-active --quiet ipsec; then
        print_info "IPsec服务已重启"
    else
        print_error "IPsec服务重启失败"
    fi
    
    if systemctl is-active --quiet xl2tpd; then
        print_info "xl2tpd服务已重启"
    else
        print_error "xl2tpd服务重启失败"
    fi
}

uninstall_vpn() {
    echo ""
    print_warning "警告: 此操作将卸载VPN服务并删除所有配置文件"
    read -p "确认卸载? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        print_info "已取消卸载操作"
        return
    fi
    
    print_info "停止服务..."
    systemctl stop strongswan 2>/dev/null || systemctl stop ipsec
    systemctl stop xl2tpd
    systemctl disable strongswan 2>/dev/null || systemctl disable ipsec
    systemctl disable xl2tpd
    
    print_info "删除配置文件..."
    rm -f /etc/ipsec.conf
    rm -f /etc/ipsec.secrets
    rm -f /etc/xl2tpd/xl2tpd.conf
    rm -f /etc/ppp/options.xl2tpd
    rm -f /etc/ppp/chap-secrets
    rm -f /root/vpn_config.txt
    
    print_info "清理防火墙规则..."
    iptables -D INPUT -p udp --dport 500 -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport 4500 -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport 1701 -j ACCEPT 2>/dev/null
    iptables -D INPUT -p esp -j ACCEPT 2>/dev/null
    
    print_info "VPN已卸载完成"
}

config_menu() {
    check_root
    set +e
    
    while true; do
        clear
        echo "=========================================="
        echo "      L2TP/IPsec VPN 配置管理"
        echo "=========================================="
        echo ""
        echo "  【用户管理】"
        echo "  1. 添加VPN用户"
        echo "  2. 删除VPN用户"
        echo "  3. 修改用户密码"
        echo "  4. 查看所有用户"
        echo ""
        echo "  【配置管理】"
        echo "  5. 查看当前配置"
        echo "  6. 修改PSK密钥"
        echo "  7. 修改L2TP配置 (IP池/本地IP)"
        echo "  8. 修改DNS服务器"
        echo "  9. 修改MTU/MRU"
        echo ""
        echo "  【服务管理】"
        echo "  10. 查看服务状态"
        echo "  11. 重启VPN服务"
        echo "  12. 卸载VPN"
        echo ""
        echo "  0. 退出"
        echo ""
        echo "=========================================="
        read -p "请选择操作 [0-12]: " choice
        
        case $choice in
            1)
                echo ""
                add_vpn_user
                read -p "按回车键继续..."
                ;;
            2)
                delete_vpn_user
                read -p "按回车键继续..."
                ;;
            3)
                modify_vpn_password
                read -p "按回车键继续..."
                ;;
            4)
                list_vpn_users
                read -p "按回车键继续..."
                ;;
            5)
                show_current_config
                read -p "按回车键继续..."
                ;;
            6)
                echo ""
                modify_psk
                read -p "按回车键继续..."
                ;;
            7)
                modify_l2tp_config
                read -p "按回车键继续..."
                ;;
            8)
                modify_dns
                read -p "按回车键继续..."
                ;;
            9)
                echo ""
                modify_mtu
                read -p "按回车键继续..."
                ;;
            10)
                show_vpn_status
                read -p "按回车键继续..."
                ;;
            11)
                echo ""
                restart_vpn_services
                read -p "按回车键继续..."
                ;;
            12)
                uninstall_vpn
                read -p "按回车键继续..."
                ;;
            0)
                print_info "退出配置管理"
                exit 0
                ;;
            *)
                print_error "无效的选择"
                sleep 1
                ;;
        esac
    done
}

main() {
    clear
    echo "=========================================="
    echo "  L2TP/IPsec VPN 一键安装脚本"
    echo "=========================================="
    echo ""
    
    check_root
    detect_os
    get_public_ip
    get_user_input
    
    echo ""
    print_info "开始安装和配置VPN服务器..."
    echo ""
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        install_packages_debian
    elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
        install_packages_centos
    else
        print_error "不支持的操作系统: $OS"
        exit 1
    fi
    
    configure_ipsec
    configure_xl2tpd
    configure_sysctl
    configure_firewall
    start_services
    show_config
    
    echo ""
    print_info "安装完成！请使用上述配置信息连接VPN"
    echo ""
    print_info "配置管理命令:"
    echo "  - 进入配置菜单: bash $0 --config"
    echo "  - 添加用户:     bash $0 --add-user"
    echo "  - 查看帮助:     bash $0 --help"
    echo ""
}

case "$1" in
    --config|--manage|-m)
        config_menu
        ;;
    --add-user)
        check_root
        add_vpn_user
        ;;
    --delete-user)
        check_root
        delete_vpn_user
        ;;
    --list-users)
        check_root
        list_vpn_users
        ;;
    --show-config)
        check_root
        show_current_config
        ;;
    --status)
        check_root
        show_vpn_status
        ;;
    --restart)
        check_root
        restart_vpn_services
        ;;
    --uninstall)
        check_root
        uninstall_vpn
        ;;
    --modify-l2tp)
        check_root
        modify_l2tp_config
        ;;
    --modify-dns)
        check_root
        modify_dns
        ;;
    --modify-mtu)
        check_root
        modify_mtu
        ;;
    --modify-psk)
        check_root
        modify_psk
        ;;
    --help|-h)
        echo "L2TP/IPsec VPN 一键安装脚本"
        echo ""
        echo "用法: bash $0 [选项]"
        echo ""
        echo "选项:"
        echo "  (无参数)          安装并配置VPN服务器"
        echo ""
        echo "  【管理菜单】"
        echo "  --config, -m      进入配置管理菜单"
        echo ""
        echo "  【用户管理】"
        echo "  --add-user        添加VPN用户"
        echo "  --delete-user     删除VPN用户"
        echo "  --list-users      查看所有用户"
        echo ""
        echo "  【配置管理】"
        echo "  --show-config     查看当前配置"
        echo "  --modify-l2tp     修改L2TP配置"
        echo "  --modify-dns      修改DNS服务器"
        echo "  --modify-mtu      修改MTU/MRU"
        echo "  --modify-psk      修改PSK密钥"
        echo ""
        echo "  【服务管理】"
        echo "  --status          查看服务状态"
        echo "  --restart         重启VPN服务"
        echo "  --uninstall       卸载VPN服务"
        echo ""
        echo "  --help, -h        显示此帮助信息"
        echo ""
        ;;
    *)
        main
        ;;
esac
