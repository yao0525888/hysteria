#!/bin/bash
RED="\033[31m"
GREEN="\033[32m\033[01m"
YELLOW="\033[33m\033[01m"
BLUE="\033[34m"
CYAN="\033[36m"
PURPLE="\033[35m"
WHITE="\033[37m"
BOLD="\033[1m"
PLAIN="\033[0m"
log_info() { echo -e "${CYAN}${WHITE}${BOLD}$1${PLAIN}"; }
log_warn() { echo -e "${YELLOW}${YELLOW}${BOLD}$1${PLAIN}"; }
log_success() { echo -e "${GREEN}${GREEN}${BOLD}$1${PLAIN}"; }
log_error() { echo -e "${RED}${RED}${BOLD}$1${PLAIN}" >&2; }
log_debug() { echo -e "${PURPLE}${PURPLE}${BOLD}$1${PLAIN}"; }
log_step() { echo -e "${WHITE}${WHITE}${BOLD}$1${PLAIN}"; }
error_exit() {
    log_error "$1"
    exit 1
}
find_openvpn_binary() {
    if [ -f /usr/sbin/openvpn ]; then
        echo "/usr/sbin/openvpn"
    elif [ -f /usr/bin/openvpn ]; then
        echo "/usr/bin/openvpn"
    else
        error_exit "未找到OpenVPN二进制文件"
    fi
}
DEFAULT_PORT=7005
DEFAULT_PROTOCOL="udp"
SERVER_IP=$(curl -s ifconfig.me)
CONFIG_DIR="/usr/local/openvpn"
SERVER_CONFIG="$CONFIG_DIR/server.conf"
CLIENT_CONFIG="$CONFIG_DIR/client.ovpn"
SILENT_MODE=true
FRP_VERSION="v0.62.1"
FRPS_PORT="7000"
FRPS_UDP_PORT="7001"
FRPS_KCP_PORT="7000"
FRPS_DASHBOARD_PORT="31410"
FRPS_TOKEN="DFRN2vbG123"
FRPS_DASHBOARD_USER="admin"
FRPS_DASHBOARD_PWD="yao58181"
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 权限运行此脚本"
    exit 1
fi
install_dependencies() {
    log_step "正在安装依赖..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update &> /dev/null
        apt-get install -y gnupg2 &> /dev/null
        curl -s https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add - &> /dev/null
        echo "deb http://build.openvpn.net/debian/openvpn/stable $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn.list
        apt-get update &> /dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn easy-rsa openssl curl wget python3 iptables-persistent &> /dev/null || error_exit "依赖安装失败"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release &> /dev/null
        yum install -y openvpn easy-rsa openssl curl wget python3 iptables-services &> /dev/null || error_exit "依赖安装失败"
    else
        error_exit "不支持的操作系统,无法安装OpenVPN依赖。"
    fi
}
generate_certificates() {
    log_step "正在生成证书..."
    mkdir -p /usr/local/openvpn/easy-rsa/ > /dev/null 2>&1 || error_exit "无法创建 easy-rsa 目录"
    cp -r /usr/share/easy-rsa/* /usr/local/openvpn/easy-rsa/ > /dev/null 2>&1 || error_exit "复制 easy-rsa 文件失败"
    cd /usr/local/openvpn/easy-rsa/ || error_exit "无法进入 easy-rsa 目录"
    ./easyrsa --batch init-pki > /dev/null 2>&1 || error_exit "初始化 PKI 失败"
    yes "" | ./easyrsa --batch build-ca nopass > /dev/null 2>&1 || error_exit "生成 CA 证书失败"
    yes "" | ./easyrsa --batch build-server-full server nopass > /dev/null 2>&1 || error_exit "生成服务器证书失败"
    yes "" | ./easyrsa --batch build-client-full client nopass > /dev/null 2>&1 || error_exit "生成客户端证书失败"
    ./easyrsa --batch gen-dh > /dev/null 2>&1 || error_exit "生成 Diffie-Hellman 参数失败"
    openvpn --genkey secret /usr/local/openvpn/ta.key > /dev/null 2>&1 || error_exit "生成 ta.key 失败"
    cp /usr/local/openvpn/easy-rsa/pki/ca.crt /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 ca.crt 失败"
    cp /usr/local/openvpn/easy-rsa/pki/issued/server.crt /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 server.crt 失败"
    cp /usr/local/openvpn/easy-rsa/pki/private/server.key /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 server.key 失败"
    cp /usr/local/openvpn/easy-rsa/pki/dh.pem /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 dh.pem 失败"
}
create_server_config() {
    log_step "正在创建服务器配置..."
    cat > $SERVER_CONFIG << EOF || error_exit "创建服务器配置文件失败"
port $DEFAULT_PORT
proto $DEFAULT_PROTOCOL
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
data-ciphers-fallback AES-256-CBC
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-auth ta.key 0
remote-cert-tls client
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
log-append openvpn.log
verb 3
EOF
}
create_client_config() {
    cat > $CLIENT_CONFIG << EOF || error_exit "创建客户端配置文件失败"
client
dev tun
proto $DEFAULT_PROTOCOL
remote $SERVER_IP $DEFAULT_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
data-ciphers-fallback AES-256-CBC
remote-cert-tls server
verb 1
<ca>
$(cat $CONFIG_DIR/easy-rsa/pki/ca.crt)
</ca>
<cert>
$(cat $CONFIG_DIR/easy-rsa/pki/issued/client.crt)
</cert>
<key>
$(cat $CONFIG_DIR/easy-rsa/pki/private/client.key)
</key>
<tls-auth>
$(cat $CONFIG_DIR/ta.key)
</tls-auth>
key-direction 1
EOF
}
setup_port_forwarding() {
    log_step "正在设置端口转发..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf && ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.d/*.conf 2>/dev/null; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf > /dev/null 2>&1
    fi
    sysctl -p > /dev/null 2>&1
    PUB_IF=$(ip -4 route list 0/0 | awk '{print $5; exit}')
    [ -z "$PUB_IF" ] && PUB_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    [ -z "$PUB_IF" ] && PUB_IF=$(ip route | grep default | awk '{print $5; exit}')
    
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${PUB_IF} -j MASQUERADE
    
    cat > /etc/iptables.rules << EOF || error_exit "创建iptables规则文件失败"
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -i tun0 -o ${PUB_IF} -j ACCEPT
-A FORWARD -i ${PUB_IF} -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.8.0.0/24 -o ${PUB_IF} -j MASQUERADE
COMMIT
EOF
    iptables-restore < /etc/iptables.rules || error_exit "应用iptables规则失败"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y iptables-persistent > /dev/null 2>&1
        mkdir -p /etc/iptables > /dev/null 2>&1
        cp /etc/iptables.rules /etc/iptables/rules.v4 > /dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y iptables-services > /dev/null 2>&1
        cp /etc/iptables.rules /etc/sysconfig/iptables > /dev/null 2>&1
        systemctl enable iptables > /dev/null 2>&1
    fi
    cat > /etc/systemd/system/iptables-restore.service << EOF || true
[Unit]
Description=Restore iptables rules
After=network.target
Before=network-online.target
[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    if [ -d /etc/network/if-pre-up.d ]; then
        echo "#!/bin/sh" > /etc/network/if-pre-up.d/iptables
        echo "iptables-restore < /etc/iptables.rules" >> /etc/network/if-pre-up.d/iptables
        chmod +x /etc/network/if-pre-up.d/iptables
    fi
    if [ -d /etc/NetworkManager/dispatcher.d ]; then
        echo "#!/bin/sh" > /etc/NetworkManager/dispatcher.d/99-iptables
        echo "iptables-restore < /etc/iptables.rules" >> /etc/NetworkManager/dispatcher.d/99-iptables
        chmod +x /etc/NetworkManager/dispatcher.d/99-iptables
    fi
    if [ -f /etc/rc.local ]; then
        if ! grep -q "iptables-restore" /etc/rc.local; then
            sed -i '/exit 0/i echo 1 > /proc/sys/net/ipv4/ip_forward\niptables-restore < /etc/iptables.rules' /etc/rc.local
        fi
    else
        echo "#!/bin/sh" > /etc/rc.local
        echo "echo 1 > /proc/sys/net/ipv4/ip_forward" >> /etc/rc.local
        echo "iptables-restore < /etc/iptables.rules" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
        chmod +x /etc/rc.local
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload > /dev/null 2>&1
        systemctl enable iptables-restore.service > /dev/null 2>&1
    fi
}
start_service() {
    log_step "正在启动 OpenVPN 服务..."
    if [ ! -f "/etc/openvpn/server/server.conf" ] && [ -f "$SERVER_CONFIG" ]; then
        mkdir -p /etc/openvpn/server/ > /dev/null 2>&1
        cp "$SERVER_CONFIG" /etc/openvpn/server/server.conf > /dev/null 2>&1
        cp "$CONFIG_DIR/ca.crt" /etc/openvpn/server/ > /dev/null 2>&1
        cp "$CONFIG_DIR/server.crt" /etc/openvpn/server/ > /dev/null 2>&1
        cp "$CONFIG_DIR/server.key" /etc/openvpn/server/ > /dev/null 2>&1
        cp "$CONFIG_DIR/dh.pem" /etc/openvpn/server/ > /dev/null 2>&1
        cp "$CONFIG_DIR/ta.key" /etc/openvpn/server/ > /dev/null 2>&1
    fi
    USE_SYSTEMD=false
    if command -v systemctl >/dev/null 2>&1 && systemctl --no-pager >/dev/null 2>&1; then
        USE_SYSTEMD=true
    fi
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    PUB_IF=$(ip -4 route list 0/0 | awk '{print $5; exit}')
    [ -z "$PUB_IF" ] && PUB_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    [ -z "$PUB_IF" ] && PUB_IF=$(ip route | grep default | awk '{print $5; exit}')
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${PUB_IF} -j MASQUERADE
    if $USE_SYSTEMD; then
        if [ ! -f /lib/systemd/system/openvpn-server@.service ] && [ ! -f /lib/systemd/system/openvpn@.service ]; then
            OPENVPN_BIN=$(find_openvpn_binary)
            cat > /etc/systemd/system/openvpn-server@.service << EOF
[Unit]
Description=OpenVPN service for %I
After=network.target
After=iptables.service
[Service]
Type=notify
PrivateTmp=true
ExecStartPre=/bin/sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
ExecStart=$OPENVPN_BIN --status /var/log/openvpn/%i-status.log --status-version 2 --suppress-timestamps --config /etc/openvpn/server/%i.conf
WorkingDirectory=/etc/openvpn/server
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
ProtectSystem=true
ProtectHome=true
KillMode=process
RestartSec=5s
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
            mkdir -p /var/log/openvpn > /dev/null 2>&1
        fi
        if systemctl list-unit-files | grep -q openvpn-server@; then
            SERVICE_NAME="openvpn-server@server"
        else
            SERVICE_NAME="openvpn@server"
        fi
        systemctl daemon-reload > /dev/null 2>&1
        systemctl enable $SERVICE_NAME > /dev/null 2>&1
        if ! systemctl restart $SERVICE_NAME > /dev/null 2>&1; then
            if [ -f /etc/openvpn/server/server.conf ]; then
                nohup $OPENVPN_BIN --config /etc/openvpn/server/server.conf > /var/log/openvpn-direct.log 2>&1 &
                sleep 2
                if pgrep -x openvpn > /dev/null; then
                    if [ -d /etc/rc.d ]; then
                        echo "#!/bin/bash" > /etc/rc.d/rc.openvpn
                        echo "echo 1 > /proc/sys/net/ipv4/ip_forward" >> /etc/rc.d/rc.openvpn
                        echo "iptables-restore < /etc/iptables.rules" >> /etc/rc.d/rc.openvpn
                        echo "$OPENVPN_BIN --config /etc/openvpn/server/server.conf --daemon" >> /etc/rc.d/rc.openvpn
                        chmod +x /etc/rc.d/rc.openvpn
                    elif [ -f /etc/rc.local ]; then
                        sed -i '/exit 0/i echo 1 > /proc/sys/net/ipv4/ip_forward\niptables-restore < /etc/iptables.rules\n'$OPENVPN_BIN' --config /etc/openvpn/server/server.conf --daemon' /etc/rc.local
                    else
                        echo "#!/bin/sh" > /etc/rc.local
                        echo "echo 1 > /proc/sys/net/ipv4/ip_forward" >> /etc/rc.local
                        echo "iptables-restore < /etc/iptables.rules" >> /etc/rc.local
                        echo "$OPENVPN_BIN --config /etc/openvpn/server/server.conf --daemon" >> /etc/rc.local
                        echo "exit 0" >> /etc/rc.local
                        chmod +x /etc/rc.local
                    fi
                else
                    error_exit "无法启动OpenVPN"
                fi
            else
                error_exit "找不到OpenVPN配置文件"
            fi
        fi
    else
        if [ -f /etc/init.d/openvpn ]; then
            update-rc.d openvpn enable > /dev/null 2>&1 || chkconfig openvpn on > /dev/null 2>&1
            /etc/init.d/openvpn restart > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                OPENVPN_BIN=$(find_openvpn_binary)
                nohup $OPENVPN_BIN --config $SERVER_CONFIG --daemon > /var/log/openvpn-direct.log 2>&1
                sleep 2
                if ! pgrep -x openvpn > /dev/null; then
                    error_exit "无法启动OpenVPN"
                fi
            fi
        else
            OPENVPN_BIN=$(find_openvpn_binary)
            nohup $OPENVPN_BIN --config $SERVER_CONFIG --daemon > /var/log/openvpn-direct.log 2>&1
            sleep 2
            if pgrep -x openvpn > /dev/null; then
                if [ -d /etc/rc.d ]; then
                    echo "#!/bin/bash" > /etc/rc.d/rc.openvpn
                    echo "echo 1 > /proc/sys/net/ipv4/ip_forward" >> /etc/rc.d/rc.openvpn
                    echo "iptables-restore < /etc/iptables.rules" >> /etc/rc.d/rc.openvpn
                    echo "$OPENVPN_BIN --config $SERVER_CONFIG --daemon" >> /etc/rc.d/rc.openvpn
                    chmod +x /etc/rc.d/rc.openvpn
                elif [ -f /etc/rc.local ]; then
                    sed -i '/exit 0/i echo 1 > /proc/sys/net/ipv4/ip_forward\niptables-restore < /etc/iptables.rules\n'$OPENVPN_BIN' --config '$SERVER_CONFIG' --daemon' /etc/rc.local
                fi
            else
                error_exit "无法启动OpenVPN"
            fi
        fi
    fi
    sleep 3
    if ! pgrep -x openvpn > /dev/null; then
        error_exit "OpenVPN服务启动失败"
    fi
}
uninstall() {
    log_step "正在卸载 OpenVPN 和 FRP..."
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop openvpn@server >/dev/null 2>&1
        systemctl stop openvpn-server@server >/dev/null 2>&1
        systemctl disable openvpn@server >/dev/null 2>&1
        systemctl disable openvpn-server@server >/dev/null 2>&1
        systemctl disable openvpn-autostart >/dev/null 2>&1
        rm -f /etc/systemd/system/openvpn-autostart.service >/dev/null 2>&1
        rm -f /etc/systemd/system/openvpn-server@.service >/dev/null 2>&1
    else
        /etc/init.d/openvpn stop >/dev/null 2>&1
        update-rc.d openvpn disable >/dev/null 2>&1 || chkconfig openvpn off >/dev/null 2>&1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop frps >/dev/null 2>&1
        systemctl disable frps >/dev/null 2>&1
        rm -f /etc/systemd/system/frps.service >/dev/null 2>&1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop iptables >/dev/null 2>&1
        systemctl disable iptables >/dev/null 2>&1
        rm -f /etc/systemd/system/iptables.service >/dev/null 2>&1
    fi
    rm -f /etc/iptables.rules >/dev/null 2>&1
    rm -rf /usr/local/openvpn >/dev/null 2>&1
    rm -rf /usr/local/frp >/dev/null 2>&1
    rm -rf /etc/frp >/dev/null 2>&1
    rm -rf /etc/openvpn >/dev/null 2>&1
    rm -f /etc/rc.d/rc.openvpn >/dev/null 2>&1
    rm -f /etc/network/if-pre-up.d/iptables >/dev/null 2>&1
    rm -f /etc/NetworkManager/dispatcher.d/99-iptables >/dev/null 2>&1
    rm -f /etc/cron.d/iptables-restore >/dev/null 2>&1
    if command -v apt-get >/dev/null 2>&1; then
        apt-get remove -y openvpn >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y openvpn >/dev/null 2>&1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1
    fi
    { pkill -9 openvpn || true; } >/dev/null 2>&1
    { pkill -9 frps || true; } >/dev/null 2>&1
    for port in $DEFAULT_PORT $FRPS_PORT $FRPS_KCP_PORT $FRPS_DASHBOARD_PORT 80; do
        local pid=$(lsof -t -i :$port 2>/dev/null)
        if [ -n "$pid" ]; then
            { kill $pid || true; } >/dev/null 2>&1
            sleep 1
            { kill -9 $pid || true; } >/dev/null 2>&1
        fi
        if command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --remove-port=$port/tcp >/dev/null 2>&1
            firewall-cmd --permanent --remove-port=$port/udp >/dev/null 2>&1
        fi
        if command -v ufw >/dev/null 2>&1; then
            ufw delete allow $port/tcp >/dev/null 2>&1
            ufw delete allow $port/udp >/dev/null 2>&1
        fi
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
    done
    if grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
        sed -i '/^net.ipv4.ip_forward=1/d' /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
    { iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $(ip route get 8.8.8.8 | awk '{print $5; exit}') -j MASQUERADE || true; } 2>/dev/null
}
change_port() {
    local new_port=$1
    log_step "正在修改端口为 $new_port..."
    sed -i "s/port [0-9]*/port $new_port/" $SERVER_CONFIG > /dev/null 2>&1 || error_exit "修改服务器端口失败"
    sed -i "s/remote $SERVER_IP [0-9]*/remote $SERVER_IP $new_port/" $CLIENT_CONFIG > /dev/null 2>&1 || error_exit "修改客户端端口失败"
    systemctl restart openvpn@server > /dev/null 2>&1 || error_exit "重启OpenVPN服务失败"
    log_success "端口已成功修改为 $new_port"
}
generate_download_link() {
    local config_path="/usr/local/openvpn/client.ovpn"
    if [ -f "$config_path" ]; then
        if lsof -i :80 > /dev/null 2>&1; then
            log_error "错误:80 端口已被占用"
            return 1
        fi
        log_success "客户端配置文件下载链接："
        log_info "http://$SERVER_IP/client.ovpn"
        mkdir -p /usr/local/openvpn || error_exit "无法创建下载目录 /usr/local/openvpn"
        (cd /usr/local/openvpn && python3 -m http.server 80 > /dev/null 2>&1 & 
         pid=$!
         sleep 600
         kill $pid 2>/dev/null) &
        return 0
    else
        log_error "客户端配置文件不存在"
        return 1
    fi
}
uninstall_frps() {
    systemctl stop frps >/dev/null 2>&1
    systemctl disable frps >/dev/null 2>&1
    rm -f /etc/systemd/system/frps.service
    rm -rf /usr/local/frp /etc/frp
    systemctl daemon-reload >/dev/null 2>&1
}
install_frps() {
    uninstall_frps
    log_step "安装FRPS服务..."
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || error_exit "无法进入/usr/local/目录"
    if ! wget "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1; then
        error_exit "FRP下载失败"
    fi
    if ! tar -zxf "${FRP_FILE}" >/dev/null 2>&1; then
        rm -f "${FRP_FILE}"
        error_exit "FRP解压失败"
    fi
    cd "${FRP_NAME}" || error_exit "无法进入FRP目录"
    rm -f frpc*
    mkdir -p /usr/local/frp || error_exit "创建/usr/local/frp目录失败"
    if ! cp frps /usr/local/frp/ >/dev/null 2>&1; then
        error_exit "拷贝frps可执行文件失败"
    fi
    chmod +x /usr/local/frp/frps >/dev/null 2>&1 || error_exit "设置frps可执行权限失败"
    mkdir -p /etc/frp || error_exit "创建/etc/frp目录失败"
    {
        echo "bindAddr = \"0.0.0.0\""
        echo "bindPort = ${FRPS_PORT}"
        echo "kcpBindPort = ${FRPS_KCP_PORT}"
        echo "auth.method = \"token\""
        echo "auth.token = \"${FRPS_TOKEN}\""
        echo "webServer.addr = \"0.0.0.0\""
        echo "webServer.port = ${FRPS_DASHBOARD_PORT}"
        echo "webServer.user = \"${FRPS_DASHBOARD_USER}\""
        echo "webServer.password = \"${FRPS_DASHBOARD_PWD}\""
        echo "enablePrometheus = true"
        echo "log.level = \"error\""
        echo "log.to = \"none\""
    } > /etc/frp/frps.toml || error_exit "写入frps.toml配置文件失败"
    {
        echo "[Unit]"
        echo "Description=Frp Server Service"
        echo "After=network.target"
        echo "[Service]"
        echo "Type=simple"
        echo "User=root"
        echo "Restart=on-failure"
        echo "RestartSec=5s"
        echo "ExecStart=/usr/local/frp/frps -c /etc/frp/frps.toml"
        echo "LimitNOFILE=1048576"
        echo "StandardOutput=null"
        echo "StandardError=null"
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } > /etc/systemd/system/frps.service || error_exit "写入frps.service文件失败"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow ${FRPS_PORT}/tcp >/dev/null 2>&1
        ufw allow ${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${FRPS_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    if ! systemctl daemon-reload >/dev/null 2>&1; then
        error_exit "Systemd daemon-reload失败"
    fi
    if ! systemctl enable --now frps >/dev/null 2>&1; then
        error_exit "启用并启动FRPS服务失败"
    fi
    log_success "FRPS安装成功"
}
show_service_info() {
    log_step "OpenVPN & FRPS服务状态:"
    systemctl status frps --no-pager | grep -E 'Active:' | sed 's/^[ \t]*//'
    if $USE_SYSTEMD; then
        if systemctl list-unit-files | grep -q openvpn-server@; then
            systemctl status openvpn-server@server --no-pager | grep -E 'Active:' | sed 's/^[ \t]*//'
        else
            systemctl status openvpn@server --no-pager | grep -E 'Active:' | sed 's/^[ \t]*//'
        fi
    else
        ps aux | grep '[o]penvpn'
    fi
    if [ -c /dev/net/tun ]; then
        log_info "TUN设备: 可用" >/dev/null 2>&1
    else
        log_info "TUN设备: 不可用 - 可能会影响OpenVPN运行"
    fi
    log_info "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    log_info "OpenVPN协议类型: ${DEFAULT_PROTOCOL}"
    log_info "OpenVPN服务端口: ${DEFAULT_PORT}"
    log_info "FRPS 端口: ${FRPS_PORT}"
    log_info "FRPS 密码: ${FRPS_TOKEN}"
    log_info "Web管理用户: ${FRPS_DASHBOARD_USER}"
    log_info "Web管理密码: ${FRPS_DASHBOARD_PWD}"
    log_info "Web管理界面: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):${FRPS_DASHBOARD_PORT}"
}
run_install() {
    install_dependencies
    generate_certificates
    create_server_config
    create_client_config
    setup_port_forwarding
    start_service
    install_frps
    echo -e "\n${GREEN}${BOLD}=== 服务信息 ===${PLAIN}"
    show_service_info
    generate_download_link
}
show_config_link() {
    if [ -f "$CLIENT_CONFIG" ]; then
        clear
        generate_download_link
        read -rp "按任意键返回主菜单..." -n1 -s
        show_menu
    else
        log_error "未找到OpenVPN客户端配置文件，请先安装OpenVPN"
        sleep 2
        show_menu
    fi
}
show_menu() {
    clear
    echo -e "${WHITE}${BOLD}OpenVPN + FRP 安装管理菜单${PLAIN}${CYAN}"
    echo -e "${GREEN}1.${PLAIN} 安装 OpenVPN 和 FRP"
    echo -e "${GREEN}2.${PLAIN} 卸载 OpenVPN 和 FRP"
    echo -e "${GREEN}3.${PLAIN} 查看 OpenVPN 配置链接"
    echo -e "${GREEN}4.${PLAIN} 退出脚本"
    read -rp "请输入选项 [1-4]: " menu_option
    case $menu_option in
        1)
            run_install
            ;;
        2)
            log_step "正在卸载 OpenVPN 和 FRP..."
            exec 3>&2
            exec 2>/dev/null
            { uninstall || true; } > /dev/null
            exec 2>&3
            log_success "卸载完成"
            sleep 3
            show_menu
            ;;
        3)
            show_config_link
            ;;
        4)
            log_info "退出脚本"
            exit 2
            ;;
        *)
            sleep 2
            show_menu
            ;;
    esac
}
if [[ "$1" == "--menu" ]]; then
    show_menu
elif [[ "$1" == "--install" ]]; then
    run_install
elif [[ "$1" == "--uninstall" ]]; then
    log_step "正在卸载 OpenVPN 和 FRP..."
    exec 3>&2
    exec 2>/dev/null
    { uninstall || true; } > /dev/null
    exec 2>&3
    log_success "卸载完成"
    sleep 2
    show_menu
else
    show_menu
fi
