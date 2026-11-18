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
apt-get install -y curl iptables >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
yum install -y curl iptables >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
dnf install -y curl iptables >/dev/null 2>&1
elif command -v pacman >/dev/null 2>&1; then
pacman -Sy --noconfirm curl iptables >/dev/null 2>&1
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
DEF_HOP_RANGE="20000-35000"
INST_NAME="实例1"
elif [[ "$1" == "2" ]]; then
SVC_NAME="hysteria-server2"
CONF_DIR="/etc/hysteria2"
CLIENT_DIR="/root/hy2"
DEF_PORT=7050
DEF_HOP_RANGE="35001-50000"
INST_NAME="实例2"
fi
}
tune_udp_sysctl() {
sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
sed -i '/net.core.rmem_default/d' /etc/sysctl.conf
sed -i '/net.core.wmem_default/d' /etc/sysctl.conf
cat <<EOF >> /etc/sysctl.conf
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
EOF
sysctl -p >/dev/null 2>&1
}
save_iptables() {
if command -v netfilter-persistent >/dev/null 2>&1; then
netfilter-persistent save >/dev/null 2>&1
elif [ -d /etc/iptables ]; then
iptables-save > /etc/iptables/rules.v4 2>/dev/null
ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
fi
}
remove_hop_rules() {
local inst_id=$1
local hop_file="$CONF_DIR/hop_range.txt"
if [ -f "$hop_file" ]; then
local old_range=$(cat "$hop_file" | tr -d ' \r\n')
local old_listen=$(grep '^listen:' "$CONF_DIR/config.yaml" 2>/dev/null | awk '{print $2}' | sed 's/://')
if [[ -n "$old_range" && -n "$old_listen" ]]; then
local old_ipt_range=$(echo "$old_range" | tr '-' ':')
iptables -t nat -D PREROUTING -p udp --dport "$old_ipt_range" -j REDIRECT --to-ports "$old_listen" >/dev/null 2>&1
ip6tables -t nat -D PREROUTING -p udp --dport "$old_ipt_range" -j REDIRECT --to-ports "$old_listen" >/dev/null 2>&1
fi
rm -f "$hop_file"
save_iptables
fi
}
apply_hop_rules() {
local inst_id=$1
local hop_range=$2
local listen_port=$3
remove_hop_rules "$inst_id"
if [[ -z "$hop_range" ]]; then return; fi
local ipt_range=$(echo "$hop_range" | tr '-' ':')
iptables -t nat -A PREROUTING -p udp --dport "$ipt_range" -j REDIRECT --to-ports "$listen_port" >/dev/null 2>&1
ip6tables -t nat -A PREROUTING -p udp --dport "$ipt_range" -j REDIRECT --to-ports "$listen_port" >/dev/null 2>&1
mkdir -p "$CONF_DIR"
echo "$hop_range" > "$CONF_DIR/hop_range.txt"
save_iptables
}
generate_client_configs() {
local inst_id=$1
local listen_port=$2
local hop_range=$3
if [[ -n $(echo $ip | grep ":") ]]; then last_ip="[$ip]"; else last_ip=$ip; fi
local server_endpoint="$last_ip:$listen_port"
local mport_param=""
if [[ -n "$hop_range" ]]; then
server_endpoint="$last_ip:$listen_port,$hop_range"
mport_param="&mport=$hop_range"
fi
mkdir -p "$CLIENT_DIR"
local node_name=$(get_ip_region "$ip")
cat << EOF > "$CLIENT_DIR/hy-client.yaml"
server: $server_endpoint
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
cat << EOF > "$CLIENT_DIR/hy-client.json"
{
  "server": "$server_endpoint",
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
local url="hy2://$HY_PASSWORD@$last_ip:$listen_port/?pinSHA256=$CERT_HASH&sni=$MASQUERADE_HOST&obfs=salamander&obfs-password=$HY_OBFS_PASSWORD${mport_param}#$node_name"
echo "$url" > "$CLIENT_DIR/url.txt"
}
install_hy2() {
set_instance_vars $1
if [[ -d "$CONF_DIR" ]]; then red "$INST_NAME 已存在"; sleep 2; menu; return; fi
read -rp "请输入 $INST_NAME 的端口 (默认 $DEF_PORT): " INST_PORT
if [[ -z "$INST_PORT" ]]; then INST_PORT=$DEF_PORT; fi
if grep -q "listen: :$INST_PORT" /etc/hysteria*/config.yaml 2>/dev/null; then red "该端口已被占用"; sleep 2; menu; return; fi
read -rp "请输入 $INST_NAME 端口跳跃范围 (直接回车启用 $DEF_HOP_RANGE, 输入 0 不启用): " HOP_INPUT
if [[ "$HOP_INPUT" == "0" ]]; then
ACTUAL_HOP=""
elif [[ -z "$HOP_INPUT" ]]; then
ACTUAL_HOP="$DEF_HOP_RANGE"
else
ACTUAL_HOP="$HOP_INPUT"
fi
ensure_curl
tune_udp_sysctl
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
if [[ -n "$ACTUAL_HOP" ]]; then
apply_hop_rules "$1" "$ACTUAL_HOP" "$INST_PORT"
fi
generate_client_configs "$1" "$INST_PORT" "$ACTUAL_HOP"
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
yellow "主端口: $INST_PORT"
if [[ -n "$ACTUAL_HOP" ]]; then
yellow "端口跳跃已启用: $ACTUAL_HOP"
else
yellow "端口跳跃: 未启用"
fi
yellow "分享链接:"
red "$(cat $CLIENT_DIR/url.txt)"
green "======================================================================================"
read -n 1 -s -r -p "按任意键返回菜单..."
else
red "服务启动失败，请检查日志" && exit 1
fi
menu
}
uninstall_hy2() {
set_instance_vars $1
remove_hop_rules $1
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
show_config() {
set_instance_vars $1
if [ ! -f "$CLIENT_DIR/url.txt" ]; then red "配置文件不存在"; sleep 2; menu; return; fi
local hop_info="未开启"
if [ -f "$CONF_DIR/hop_range.txt" ]; then hop_info=$(cat "$CONF_DIR/hop_range.txt"); fi
green "======================================================================================"
yellow "当前端口跳跃状态: $hop_info"
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
menu
}
change_port() {
set_instance_vars $1
read -rp "请输入新的主端口号: " new_port
if [[ ! $new_port =~ ^[0-9]+$ ]] || [[ $new_port -lt 1 ]] || [[ $new_port -gt 65535 ]]; then
red "端口号无效"
sleep 2
menu
return
fi
if [ -f $CONF_DIR/config.yaml ]; then sed -i "s/^listen: :[0-9]\+/listen: :$new_port/" $CONF_DIR/config.yaml; fi
realip
local current_hop=""
if [ -f "$CONF_DIR/hop_range.txt" ]; then
current_hop=$(cat "$CONF_DIR/hop_range.txt")
apply_hop_rules "$1" "$current_hop" "$new_port"
fi
generate_client_configs "$1" "$new_port" "$current_hop"
echo -e "${YELLOW}正在重启服务以应用新端口...${PLAIN}"
systemctl restart ${SVC_NAME}
if [[ -n $(systemctl status ${SVC_NAME} 2>/dev/null | grep -w active) ]]; then
green "======================================================================================"
green "端口已修改为 $new_port，服务已自动重启！"
if [ -f $CLIENT_DIR/url.txt ]; then
yellow "分享链接:"
red "$(cat $CLIENT_DIR/url.txt)"
fi
green "======================================================================================"
read -n 1 -s -r -p "按任意键返回菜单..."
else
red "服务重启失败，请检查端口是否被占用！"
sleep 2
fi
menu
}
configure_port_hopping() {
set_instance_vars $1
clear
local current_hop="未开启"
if [ -f "$CONF_DIR/hop_range.txt" ]; then current_hop=$(cat "$CONF_DIR/hop_range.txt"); fi
local current_listen=$(grep '^listen:' "$CONF_DIR/config.yaml" 2>/dev/null | awk '{print $2}' | sed 's/://')
[ -z "$current_listen" ] && current_listen=$DEF_PORT
echo "#############################################################"
echo -e "#            ${GREEN}配置端口跳跃 (Port Hopping): $INST_NAME${PLAIN}            #"
echo "#############################################################"
echo -e " 主监听端口: ${YELLOW}$current_listen${PLAIN}"
echo -e " 当前端口跳跃状态: ${GREEN}$current_hop${PLAIN}"
echo -e " 默认推荐范围: ${YELLOW}$DEF_HOP_RANGE${PLAIN}"
echo -e " ${GREEN}1.${PLAIN} 启用/修改 端口跳跃"
echo -e " ${RED}2.${PLAIN} 关闭 端口跳跃"
echo -e " ${GREEN}0.${PLAIN} 返回上一级"
read -rp "请选择操作 [0-2]: " hop_opt
case $hop_opt in
1)
read -rp "请输入端口跳跃范围 (格式: 起始-结束，直接回车使用 $DEF_HOP_RANGE): " user_range
if [[ -z "$user_range" ]]; then user_range="$DEF_HOP_RANGE"; fi
if [[ ! "$user_range" =~ ^[0-9]+-[0-9]+$ ]]; then
red "格式错误！必须为 起始-结束 (例如: 20000-35000)"
sleep 2
menu
return
fi
ensure_curl
tune_udp_sysctl
apply_hop_rules "$1" "$user_range" "$current_listen"
realip
generate_client_configs "$1" "$current_listen" "$user_range"
green "端口跳跃已成功应用: $user_range"
if [ -f "$CLIENT_DIR/url.txt" ]; then
yellow "更新后的分享链接:"
red "$(cat $CLIENT_DIR/url.txt)"
fi
read -n 1 -s -r -p "按任意键返回菜单..."
;;
2)
remove_hop_rules "$1"
realip
generate_client_configs "$1" "$current_listen" ""
green "端口跳跃已成功关闭并注销重定向规则！"
if [ -f "$CLIENT_DIR/url.txt" ]; then
yellow "更新后的分享链接:"
red "$(cat $CLIENT_DIR/url.txt)"
fi
read -n 1 -s -r -p "按任意键返回菜单..."
;;
0)
menu
return
;;
*)
menu
return
;;
esac
menu
}
menu() {
clear
echo "#############################################################"
echo -e "#                 ${GREEN}Hysteria 2 双实例管理脚本${PLAIN}                 #"
echo "#############################################################"
echo -e " ${YELLOW}--- 实例 1 (默认) ---${PLAIN}"
echo -e " ${GREEN}1.${PLAIN} 安装 实例1"
echo -e " ${RED}2.${PLAIN} 卸载 实例1"
echo -e " ${GREEN}3.${PLAIN} 查看 实例1 配置及分享链接"
echo -e " ${GREEN}4.${PLAIN} 修改 实例1 端口"
echo -e " ${GREEN}5.${PLAIN} 配置/开关 实例1 端口跳跃"
echo -e " ${YELLOW}--- 实例 2 ---${PLAIN}"
echo -e " ${GREEN}6.${PLAIN} 安装 实例2"
echo -e " ${RED}7.${PLAIN} 卸载 实例2"
echo -e " ${GREEN}8.${PLAIN} 查看 实例2 配置及分享链接"
echo -e " ${GREEN}9.${PLAIN} 修改 实例2 端口"
echo -e " ${GREEN}10.${PLAIN} 配置/开关 实例2 端口跳跃"
echo -e " ${GREEN}0.${PLAIN} 退出"
read -rp "请输入选项 [0-10]: " menuInput
case $menuInput in
1) install_hy2 1 ;;
2) if [[ -d "/etc/hysteria" ]]; then uninstall_hy2 1; else red "实例1未安装"; sleep 2; menu; fi ;;
3) if [[ -d "/etc/hysteria" ]]; then show_config 1; else red "实例1未安装"; sleep 2; menu; fi ;;
4) if [[ -d "/etc/hysteria" ]]; then change_port 1; else red "实例1未安装"; sleep 2; menu; fi ;;
5) if [[ -d "/etc/hysteria" ]]; then configure_port_hopping 1; else red "实例1未安装"; sleep 2; menu; fi ;;
6) install_hy2 2 ;;
7) if [[ -d "/etc/hysteria2" ]]; then uninstall_hy2 2; else red "实例2未安装"; sleep 2; menu; fi ;;
8) if [[ -d "/etc/hysteria2" ]]; then show_config 2; else red "实例2未安装"; sleep 2; menu; fi ;;
9) if [[ -d "/etc/hysteria2" ]]; then change_port 2; else red "实例2未安装"; sleep 2; menu; fi ;;
10) if [[ -d "/etc/hysteria2" ]]; then configure_port_hopping 2; else red "实例2未安装"; sleep 2; menu; fi ;;
0) exit 0 ;;
*) menu ;;
esac
}
menu