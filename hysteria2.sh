#!/bin/bash
export LANG=en_US.UTF-8
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"
MASQUERADE_HOST=www.bing.com
HY_PASSWORD=9e264d67-fe47-4d2f-b55e-631a12e46a30
HY_OBFS_PASSWORD=wGW1duwjo7gWV0F4aqJu44jJBG4ELk3WNgbs3ATJu3M
CERT_HASH=ba515ecab2b16e232f66d7f504415833f3669605c4c416f957906156e75e8cd6
red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }
ensure_curl() {
    if command -v curl >/dev/null 2>&1; then return; fi
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm curl >/dev/null 2>&1
    else
        exit 1
    fi
}
realip(){ ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k); }
declare -A COUNTRY_MAP=( ["US"]="美国" ["CN"]="中国" ["HK"]="香港" ["TW"]="台湾" ["JP"]="日本" ["KR"]="韩国" ["SG"]="新加坡" ["AU"]="澳大利亚" ["DE"]="德国" ["GB"]="英国" ["CA"]="加拿大" ["FR"]="法国" ["IN"]="印度" ["IT"]="意大利" ["RU"]="俄罗斯" ["BR"]="巴西" ["NL"]="荷兰" ["SE"]="瑞典" ["NO"]="挪威" ["FI"]="芬兰" ["DK"]="丹麦" ["CH"]="瑞士" ["ES"]="西班牙" ["PT"]="葡萄牙" ["AT"]="奥地利" ["BE"]="比利时" ["IE"]="爱尔兰" ["PL"]="波兰" ["NZ"]="新西兰" ["MX"]="墨西哥" ["ID"]="印度尼西亚" ["TH"]="泰国" ["VN"]="越南" ["MY"]="马来西亚" ["PH"]="菲律宾" ["TR"]="土耳其" ["AE"]="阿联酋" ["SA"]="沙特阿拉伯" ["ZA"]="南非" ["IL"]="以色列" ["UA"]="乌克兰" ["GR"]="希腊" ["CZ"]="捷克" ["HU"]="匈牙利" ["RO"]="罗马尼亚" ["BG"]="保加利亚" ["HR"]="克罗地亚" ["RS"]="塞尔维亚" ["EE"]="爱沙尼亚" ["LV"]="拉脱维亚" ["LT"]="立陶宛" ["SK"]="斯洛伐克" ["SI"]="斯洛文尼亚" ["IS"]="冰岛" ["LU"]="卢森堡" ["UK"]="英国" )
get_ip_region() {
    local ip=$1
    if [[ -z "$ip" ]]; then realip; fi
    local country_code=""
    country_code=$(curl -s -m 5 "https://ipinfo.io/${ip}/json" | grep -o '"country":"[^\"]*"' | cut -d ':' -f2 | tr -d '",')
    if [[ -z "$country_code" ]]; then country_code=$(curl -s -m 5 "https://api.ip.sb/geoip/${ip}" | grep -o '"country_code":"[^\"]*"' | cut -d ':' -f2 | tr -d '",'); fi
    if [[ -z "$country_code" ]]; then
        country_code=$(curl -s -m 5 "https://ipapi.co/${ip}/country")
        if [[ "$country_code" == *"error"* || "$country_code" == *"reserved"* ]]; then country_code=""; fi
    fi
    if [[ -z "$country_code" ]]; then country_code=$(curl -s -m 5 "http://ip-api.com/json/${ip}?fields=countryCode" | grep -o '"countryCode":"[^\"]*"' | cut -d ':' -f2 | tr -d '",'); fi
    if [[ -n "$country_code" ]]; then
        local country_name="${COUNTRY_MAP[$country_code]}"
        if [[ -n "$country_name" ]]; then echo "$country_name"; return; fi
    fi
    echo "国外"
}
set_instance_vars() {
    if [[ "$1" == "1" ]]; then
        SVC_NAME="hysteria-server"
        CONF_DIR="/etc/hysteria"
        CLIENT_DIR="/root/hy"
        DEF_PORT=8443
        INST_NAME="实例1"
    elif [[ "$1" == "2" ]]; then
        SVC_NAME="hysteria-server2"
        CONF_DIR="/etc/hysteria2"
        CLIENT_DIR="/root/hy2"
        DEF_PORT=7007
        INST_NAME="实例2"
    fi
}
install_hy2() {
    set_instance_vars $1
    if [[ -d "$CONF_DIR" ]]; then red "$INST_NAME 已存在"; sleep 2; menu; return; fi
    read -rp "请输入 $INST_NAME 的端口 (默认 $DEF_PORT): " INST_PORT
    if [[ -z "$INST_PORT" ]]; then INST_PORT=$DEF_PORT; fi
    if grep -q "listen: :$INST_PORT" /etc/hysteria*/config.yaml 2>/dev/null; then red "该端口已被占用"; sleep 2; menu; return; fi
    ensure_curl
    systemctl stop vpn >/dev/null 2>&1
    systemctl disable vpn >/dev/null 2>&1
    rm -f /etc/systemd/system/vpn.service
    if pgrep vpnserver > /dev/null; then /usr/local/vpnserver/vpnserver stop >/dev/null 2>&1; fi
    rm -rf /usr/local/vpnserver /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log
    systemctl daemon-reload >/dev/null 2>&1
    realip
    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh > /dev/null 2>&1
    bash install_server.sh > /dev/null 2>&1
    rm -f install_server.sh
    if [[ ! -f "/usr/local/bin/hysteria" ]]; then red "Hysteria 2 安装失败！" && exit 1; fi
    mkdir -p $CONF_DIR
    if [[ ! -f $CONF_DIR/cert.crt ]]; then
        wget -O $CONF_DIR/cert.crt https://github.com/yao0525888/hysteria/releases/download/v1/cert.crt >/dev/null 2>&1
        wget -O $CONF_DIR/private.key https://github.com/yao0525888/hysteria/releases/download/v1/private.key >/dev/null 2>&1
        chmod 644 $CONF_DIR/cert.crt $CONF_DIR/private.key
    fi
    cat << EOF > $CONF_DIR/config.yaml
listen: :$INST_PORT
tls:
  cert: $CONF_DIR/cert.crt
  key: $CONF_DIR/private.key
quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432
obfs:
  type: salamander
  salamander:
    password: "$HY_OBFS_PASSWORD"
auth:
  type: password
  password: "$HY_PASSWORD"
masquerade:
  type: proxy
  proxy:
    url: https://$MASQUERADE_HOST
    rewriteHost: true
EOF
    if [[ -n $(echo $ip | grep ":") ]]; then last_ip="[$ip]"; else last_ip=$ip; fi
    mkdir -p $CLIENT_DIR
    node_name=$(get_ip_region "$ip")
    cat << EOF > $CLIENT_DIR/hy-client.yaml
server: $last_ip:$INST_PORT
auth:
  type: password
  password: "$HY_PASSWORD"
obfs:
  type: salamander
  salamander:
    password: "$HY_OBFS_PASSWORD"
tls:
  sni: $MASQUERADE_HOST
  pinnedPeerCertSha256: $CERT_HASH
quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432
fastOpen: true
socks5:
  listen: 127.0.0.1:5678
transport:
  udp:
    hopInterval: 30s 
EOF
    cat << EOF > $CLIENT_DIR/hy-client.json
{
  "server": "$last_ip:$INST_PORT",
  "auth": {
    "type": "password",
    "password": "$HY_PASSWORD"
  },
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "$HY_OBFS_PASSWORD"
    }
  },
  "tls": {
    "sni": "$MASQUERADE_HOST",
    "pinnedPeerCertSha256": "$CERT_HASH"
  },
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "socks5": {
    "listen": "127.0.0.1:5678"
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF
    url="hy2://$HY_PASSWORD@$last_ip:$INST_PORT/?pinSHA256=$CERT_HASH&sni=$MASQUERADE_HOST&obfs=salamander&obfs-password=$HY_OBFS_PASSWORD#$node_name"
    echo $url > $CLIENT_DIR/url.txt
    cat > /etc/systemd/system/${SVC_NAME}.service << EOF
[Unit]
Description=Hysteria 2 Server ($INST_NAME)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c $CONF_DIR/config.yaml
Restart=on-failure
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${SVC_NAME} > /dev/null 2>&1
    systemctl start ${SVC_NAME}
    if [[ -n $(systemctl status ${SVC_NAME} 2>/dev/null | grep -w active) ]]; then
        green "======================================================================================"
        green "Hysteria 2 $INST_NAME 安装成功！"
        yellow "端口: $INST_PORT"
        yellow "分享链接:"
        red "$url"
        green "======================================================================================"
        read -n 1 -s -r -p "按任意键返回菜单..."
    else
        red "服务启动失败，请检查日志" && exit 1
    fi
    menu
}
uninstall_hy2() {
    set_instance_vars $1
    systemctl stop ${SVC_NAME} >/dev/null 2>&1
    systemctl disable ${SVC_NAME} >/dev/null 2>&1
    rm -f /etc/systemd/system/${SVC_NAME}.service
    rm -rf $CONF_DIR $CLIENT_DIR
    if [ ! -d "/etc/hysteria" ] && [ ! -d "/etc/hysteria2" ]; then
        rm -rf /usr/local/bin/hysteria
    fi
    systemctl daemon-reload
    green "$INST_NAME 已完全卸载！"
    sleep 2
    menu
}
start_hy2() {
    set_instance_vars $1
    systemctl start ${SVC_NAME}
    if [[ -n $(systemctl status ${SVC_NAME} 2>/dev/null | grep -w active) ]]; then green "$INST_NAME 已启动"; else red "$INST_NAME 启动失败"; fi
}
stop_hy2() {
    set_instance_vars $1
    systemctl stop ${SVC_NAME}
    green "$INST_NAME 已停止"
}
restart_hy2() {
    set_instance_vars $1
    systemctl restart ${SVC_NAME}
    if [[ -n $(systemctl status ${SVC_NAME} 2>/dev/null | grep -w active) ]]; then green "$INST_NAME 已重启"; else red "$INST_NAME 重启失败"; fi
}
show_config() {
    set_instance_vars $1
    if [ ! -f "$CLIENT_DIR/url.txt" ]; then red "配置文件不存在"; sleep 2; return; fi
    green "======================================================================================"
    if [ -f "$CLIENT_DIR/hy-client.yaml" ]; then
        yellow "YAML配置文件 ($CLIENT_DIR/hy-client.yaml):"
        cat $CLIENT_DIR/hy-client.yaml
        echo ""
    fi
    if [ -f "$CLIENT_DIR/url.txt" ]; then
        yellow "分享链接:"
        red "$(cat $CLIENT_DIR/url.txt)"
    fi
    green "======================================================================================"
    read -n 1 -s -r -p "按任意键返回菜单..."
}
change_port() {
    set_instance_vars $1
    read -rp "请输入新的端口号: " new_port
    if [[ ! $new_port =~ ^[0-9]+$ ]] || [[ $new_port -lt 1 ]] || [[ $new_port -gt 65535 ]]; then
        red "端口号无效"
        sleep 2
        menu
        return
    fi
    if [ -f $CONF_DIR/config.yaml ]; then sed -i "s/^listen: :[0-9]\+/listen: :$new_port/" $CONF_DIR/config.yaml; fi
    if [ -f $CLIENT_DIR/hy-client.yaml ]; then sed -i "s/^server: \(.*\):[0-9]\+/server: \1:$new_port/" $CLIENT_DIR/hy-client.yaml; fi
    if [ -f $CLIENT_DIR/hy-client.json ]; then sed -i "s/\(\"server\": \".*:\)[0-9]\+\(\"\)/\1$new_port\2/" $CLIENT_DIR/hy-client.json; fi
    if [ -f $CLIENT_DIR/url.txt ]; then sed -i "s/\(@.*:\)[0-9]\+\//\1$new_port\//" $CLIENT_DIR/url.txt; fi
    echo -e "${YELLOW}正在重启服务以应用新端口...${PLAIN}"
    systemctl restart ${SVC_NAME}
    if [[ -n $(systemctl status ${SVC_NAME} 2>/dev/null | grep -w active) ]]; then
        green "端口已修改为 $new_port，服务已自动重启！"
    else
        red "服务重启失败，请检查端口是否被占用！"
    fi
    sleep 2
    menu
}
instance_control_menu() {
    set_instance_vars $1
    clear
    echo "#############################################################"
    echo -e "#               ${GREEN}独立管理菜单: $INST_NAME${PLAIN}                   #"
    echo "#############################################################"
    echo -e " ${GREEN}1.${PLAIN} 启动该实例"
    echo -e " ${GREEN}2.${PLAIN} 停止该实例"
    echo -e " ${GREEN}3.${PLAIN} 重启该实例"
    echo -e " ${GREEN}4.${PLAIN} 显示配置及分享链接"
    echo -e " ${GREEN}0.${PLAIN} 返回主菜单"
    read -rp "请输入选项 [0-4]: " action
    case $action in
        1) start_hy2 $1; sleep 2; instance_control_menu $1 ;;
        2) stop_hy2 $1; sleep 2; instance_control_menu $1 ;;
        3) restart_hy2 $1; sleep 2; instance_control_menu $1 ;;
        4) show_config $1; instance_control_menu $1 ;;
        0) menu ;;
        *) instance_control_menu $1 ;;
    esac
}
menu() {
    clear
    echo "#############################################################"
    echo -e "#                 ${GREEN}Hysteria 2 双实例管理脚本${PLAIN}                 #"
    echo "#############################################################"
    echo -e " ${YELLOW}--- 实例 1 (默认) ---${PLAIN}"
    echo -e " ${GREEN}1.${PLAIN} 安装 实例1"
    echo -e " ${RED}2.${PLAIN} 卸载 实例1"
    echo -e " ${GREEN}3.${PLAIN} 管理 实例1 (启停/配置)"
    echo -e " ${GREEN}4.${PLAIN} 修改 实例1 端口"
    echo -e " ${YELLOW}--- 实例 2 ---${PLAIN}"
    echo -e " ${GREEN}5.${PLAIN} 安装 实例2"
    echo -e " ${RED}6.${PLAIN} 卸载 实例2"
    echo -e " ${GREEN}7.${PLAIN} 管理 实例2 (启停/配置)"
    echo -e " ${GREEN}8.${PLAIN} 修改 实例2 端口"
    echo "-------------------------------------------------------------"
    echo -e " ${GREEN}0.${PLAIN} 退出"
    read -rp "请输入选项 [0-8]: " menuInput
    case $menuInput in
        1) install_hy2 1 ;;
        2) if [[ -d "/etc/hysteria" ]]; then uninstall_hy2 1; else red "实例1未安装"; sleep 2; menu; fi ;;
        3) if [[ -d "/etc/hysteria" ]]; then instance_control_menu 1; else red "实例1未安装"; sleep 2; menu; fi ;;
        4) if [[ -d "/etc/hysteria" ]]; then change_port 1; else red "实例1未安装"; sleep 2; menu; fi ;;
        5) install_hy2 2 ;;
        6) if [[ -d "/etc/hysteria2" ]]; then uninstall_hy2 2; else red "实例2未安装"; sleep 2; menu; fi ;;
        7) if [[ -d "/etc/hysteria2" ]]; then instance_control_menu 2; else red "实例2未安装"; sleep 2; menu; fi ;;
        8) if [[ -d "/etc/hysteria2" ]]; then change_port 2; else red "实例2未安装"; sleep 2; menu; fi ;;
        0) exit 0 ;;
        *) menu ;;
    esac
}
menu
