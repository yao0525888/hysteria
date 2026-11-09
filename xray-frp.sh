#!/bin/bash
LIGHT_GREEN='\033[1;32m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
declare -A COUNTRY_MAP=(
    ["US"]="美国" ["CN"]="中国" ["HK"]="香港" ["TW"]="台湾" ["JP"]="日本" ["KR"]="韩国"
    ["SG"]="新加坡" ["AU"]="澳大利亚" ["DE"]="德国" ["GB"]="英国" ["CA"]="加拿大" ["FR"]="法国"
    ["IN"]="印度" ["IT"]="意大利" ["RU"]="俄罗斯" ["BR"]="巴西" ["NL"]="荷兰" ["SE"]="瑞典"
    ["NO"]="挪威" ["FI"]="芬兰" ["DK"]="丹麦" ["CH"]="瑞士" ["ES"]="西班牙" ["PT"]="葡萄牙"
    ["AT"]="奥地利" ["BE"]="比利时" ["IE"]="爱尔兰" ["PL"]="波兰" ["NZ"]="新西兰" ["MX"]="墨西哥"
    ["ID"]="印度尼西亚" ["TH"]="泰国" ["VN"]="越南" ["MY"]="马来西亚" ["PH"]="菲律宾"
)
FRP_VERSION="v0.66.0"
XRAY_VERSION="v25.9.11"
FRPS_PORT="7006"
SILENT_MODE=true
gen_frps_token() {
    echo "DFRN2vbG123"
}
FRPS_TOKEN=$(gen_frps_token)
log_info() {
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${BLUE}[INFO]${NC} $1"
}
log_step() {
    echo -e "${YELLOW}[$1/$2] $3${NC}"
}
log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}
log_error() {
    echo -e "${RED}[错误]${NC} $1"
    exit 1
}
log_sub_step() {
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${GREEN}[$1/$2]$3${NC}"
}
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 或 root 权限运行脚本"
    fi
}
install_dependencies() {
    [ "$EUID" -ne 0 ] && exit 1
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        command -v unzip >/dev/null 2>&1 || apt-get install -y unzip >/dev/null 2>&1
        command -v wget  >/dev/null 2>&1 || apt-get install -y wget  >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        command -v unzip >/dev/null 2>&1 || dnf install -y unzip >/dev/null 2>&1
        command -v wget  >/dev/null 2>&1 || dnf install -y wget  >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        command -v unzip >/dev/null 2>&1 || yum install -y unzip >/dev/null 2>&1
        command -v wget  >/dev/null 2>&1 || yum install -y wget  >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        command -v unzip >/dev/null 2>&1 || pacman -S --noconfirm unzip >/dev/null 2>&1
        command -v wget  >/dev/null 2>&1 || pacman -S --noconfirm wget  >/dev/null 2>&1
    else
        exit 1
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
    log_step "1" "2" "安装FRPS服务..."
    cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -p >/dev/null 2>&1
    uninstall_frps
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || exit 1
    if ! wget "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1; then
        exit 1
    fi
    if ! tar -zxf "${FRP_FILE}" >/dev/null 2>&1; then
        rm -f "${FRP_FILE}"
        exit 1
    fi
    cd "${FRP_NAME}" || exit 1
    mkdir -p /usr/local/frp || exit 1
    if ! cp frps /usr/local/frp/ >/dev/null 2>&1; then
        exit 1
    fi
    chmod +x /usr/local/frp/frps
    mkdir -p /etc/frp || exit 1
    {
        echo "bindAddr = \"0.0.0.0\""
        echo "bindPort = 7006"
        echo "auth.method = \"token\""
        echo "auth.token = \"$FRPS_TOKEN\""
    } > /etc/frp/frps.toml || exit 1
    {
        echo "[Unit]"
        echo "Description=FRP Server"
        echo "After=network.target"
        echo "[Service]"
        echo "Type=simple"
        echo "ExecStart=/usr/local/frp/frps -c /etc/frp/frps.toml"
        echo "Restart=on-failure"
        echo "LimitNOFILE=1048576"
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } > /etc/systemd/system/frps.service || exit 1
    if ! systemctl daemon-reload >/dev/null 2>&1; then
        exit 1
    fi
    if ! systemctl enable --now frps >/dev/null 2>&1; then
        echo -e "${RED}FRPS启动失败${NC}"
        exit 1
    fi
    log_success "FRPS安装成功"
}
install_xray() {
    log_step "2" "2" "安装Xray服务..."
    uninstall_xray
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        armv7l) ARCH="arm32-v7a" ;;
        *) log_error "不支持的架构" ;;
    esac
    VER=$XRAY_VERSION
    URL="https://github.com/XTLS/Xray-core/releases/download/$VER/Xray-linux-$ARCH.zip"
    wget -q -O xray.zip $URL
    if [ ! -s xray.zip ]; then
        log_error "Xray 下载失败"
    fi
    if ! unzip -q -o xray.zip; then
        log_error "Xray 解压失败"
    fi
    if [ ! -f xray ]; then
        log_error "Xray 主程序未找到"
    fi
    chmod +x xray
    mv xray /usr/local/bin/ >/dev/null 2>&1
    mv geoip.dat geosite.dat /usr/local/bin/ >/dev/null 2>&1
    rm -f xray.zip LICENSE README.md >/dev/null 2>&1
    SHORTID="abcdef12"
    UUID="9e264d67-fe47-4d2f-b55e-631a12e46a30"
    PRIVATE_KEY="SBznh0LAR5I-Xo2XDMAJrCC_UoS1Wb7gjycfKTFyZmA"
    PUBLIC_KEY="n5cQsnGAxadThor3_U5fIFafC24rA0-OrA3vQj06onU"
    PORT=443
    FLOW="xtls-rprx-vision"
    SNI="www.apple.com"
    DOMAIN=$(curl -s ifconfig.me)
    COUNTRY_CODE=$(curl -s "https://ipinfo.io/$DOMAIN/country")
    REGION=${COUNTRY_MAP[$COUNTRY_CODE]}
    [ -z "$REGION" ] && REGION="$COUNTRY_CODE"
    mkdir -p /usr/local/etc/xray >/dev/null 2>&1
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": $PORT,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "$FLOW"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:$PORT",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORTID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    systemctl start xray >/dev/null 2>&1
    log_success "Xray启动成功"
}
cleanup() {
    rm -rf /usr/local/frp_* /usr/local/frp_*_linux_amd64
}
show_results() {
    echo -e "\n${YELLOW}>>> FRPS服务状态：${NC}"
    systemctl is-active frps
    echo -e "\n${YELLOW}>>> Xray服务状态：${NC}"
    systemctl is-active xray
    echo -e "\n${YELLOW}>>> FRPS信息：${NC}"
    echo -e "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    echo -e "FRPS 密码: $FRPS_TOKEN"
    echo -e "TCP端口: 7006"
    echo -e "\n${YELLOW}>>> Xray Reality 分享链接：${NC}"
    LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=$FLOW&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORTID&type=tcp#$REGION"
    echo -e "${GREEN}$LINK${NC}\n"
}
uninstall_xray() {
    systemctl stop xray >/dev/null 2>&1
    systemctl disable xray >/dev/null 2>&1
    rm -f /etc/systemd/system/xray.service
    rm -rf /usr/local/etc/xray
    rm -f /usr/local/bin/xray
    rm -f /usr/local/bin/geoip.dat
    rm -f /usr/local/bin/geosite.dat
    systemctl daemon-reload >/dev/null 2>&1
}
restart_services() {
    echo -e "\n${YELLOW}>>> 正在重启服务...${NC}"
    systemctl daemon-reload >/dev/null 2>&1
    systemctl restart xray
    if [ -f /etc/systemd/system/frps.service ] || systemctl is-active --quiet frps 2>/dev/null; then
        systemctl restart frps >/dev/null 2>&1
    fi
    sleep 1
    if systemctl is-active --quiet xray; then
        log_success "Xray 服务重启成功！"
    else
        echo -e "${RED}[错误] Xray 服务重启失败，请检查配置文件！${NC}"
        systemctl status xray --no-pager
    fi
    if systemctl is-active --quiet frps 2>/dev/null; then
        log_success "FRPS 服务重启成功！"
    fi
}
get_xray_shortid() {
    local cfg="/usr/local/etc/xray/config.json"
    [ ! -f "$cfg" ] && return
    local sid=""
    if command -v jq >/dev/null 2>&1; then
        sid=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$cfg" 2>/dev/null)
    fi
    if [ -z "$sid" ] || [ "$sid" = "null" ]; then
        sid=$(sed -n '/"shortIds"/,/\]/{ /"shortIds"[^[]*\[/s/.*\[[[:space:]]*"\([^"]*\)".*/\1/p; /"shortIds"/d; /"[^"]*"/s/.*"\([^"]*\)".*/\1/p }' "$cfg" 2>/dev/null | head -n 1)
    fi
    echo "$sid"
}
get_xray_sni() {
    local cfg="/usr/local/etc/xray/config.json"
    [ ! -f "$cfg" ] && return
    local sni=""
    if command -v jq >/dev/null 2>&1; then
        sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$cfg" 2>/dev/null)
    fi
    if [ -z "$sni" ] || [ "$sni" = "null" ]; then
        sni=$(sed -n '/"serverNames"/,/\]/{ /"serverNames"/d; /"[^"]*"/s/.*"\([^"]*\)".*/\1/p }' "$cfg" 2>/dev/null | head -n 1)
    fi
    if [ -z "$sni" ]; then
        sni=$(sed -n 's/.*"dest": *"\([^:]*\):.*/\1/p' "$cfg" 2>/dev/null | head -n 1)
    fi
    echo "$sni"
}
modify_xray_port() {
    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo -e "${RED}[错误] 未检测到 Xray 配置文件，请先安装 Xray${NC}"
        return
    fi
    read -p "请输入新的端口号(1-65535): " NEW_PORT
    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ]] || [ "$NEW_PORT" -gt 65535 ]; then
        echo -e "${RED}[错误] 无效的端口号${NC}"
        return
    fi
    if netstat -tuln 2>/dev/null | grep -q ":$NEW_PORT "; then
        echo -e "${RED}[错误] 端口 $NEW_PORT 已被占用${NC}"
        return
    fi
    sed -i "s/\"port\": [0-9]*/\"port\": $NEW_PORT/" /usr/local/etc/xray/config.json
    sed -i "s/\"dest\": \"\([^\"]*\):[0-9]*\"/\"dest\": \"\1:$NEW_PORT\"/" /usr/local/etc/xray/config.json
    restart_services
    log_success "Xray端口已修改为: $NEW_PORT"
    show_xray_link
}
modify_xray_shortid() {
    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo -e "${RED}[错误] 未检测到 Xray 配置文件，请先安装 Xray${NC}"
        return
    fi
    local current_sid=$(get_xray_shortid)
    echo -e "\n当前 SHORTID: ${GREEN}${current_sid:-无}${NC}"
    read -p "请输入新的 SHORTID: " NEW_SHORTID
    if [ -z "$NEW_SHORTID" ]; then
        if command -v openssl >/dev/null 2>&1; then
            NEW_SHORTID=$(openssl rand -hex 4)
        else
            NEW_SHORTID=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 8)
        fi
        echo -e "已随机生成 SHORTID: ${GREEN}$NEW_SHORTID${NC}"
    else
        if ! [[ "$NEW_SHORTID" =~ ^[0-9a-fA-F]+$ ]] || [ ${#NEW_SHORTID} -gt 16 ] || [ $((${#NEW_SHORTID} % 2)) -ne 0 ]; then
            echo -e "${RED}[错误] 无效的 SHORTID！必须是偶数长度(最长16位)的十六进制字符 (0-9, a-f)${NC}"
            return
        fi
        NEW_SHORTID=$(echo "$NEW_SHORTID" | tr 'A-F' 'a-f')
    fi
    if command -v jq >/dev/null 2>&1; then
        jq --arg sid "$NEW_SHORTID" '.inbounds[0].streamSettings.realitySettings.shortIds = [$sid]' /usr/local/etc/xray/config.json > /usr/local/etc/xray/config.json.tmp && mv /usr/local/etc/xray/config.json.tmp /usr/local/etc/xray/config.json
    else
        if grep -q '"shortIds"[^[]*\[ *"[^"]*"' /usr/local/etc/xray/config.json; then
            sed -i 's/\("shortIds"[^[]*\[ *"\)[^"]*/\1'"$NEW_SHORTID"'/' /usr/local/etc/xray/config.json
        else
            sed -i '/"shortIds"/,/\]/{ /"shortIds"/!s/"[^"]*"/"'"$NEW_SHORTID"'"/ }' /usr/local/etc/xray/config.json
        fi
    fi
    restart_services
    log_success "SHORTID已修改为: $NEW_SHORTID"
    show_xray_link
}
modify_xray_sni() {
    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo -e "${RED}[错误] 未检测到 Xray 配置文件，请先安装 Xray${NC}"
        return
    fi
    local current_sni=$(get_xray_sni)
    echo -e "\n${YELLOW}=== 修改 Xray SNI 菜单 ===${NC}"
    echo -e "当前 SNI: ${GREEN}${current_sni:-www.apple.com}${NC}"
    echo -e "${GREEN}1.${NC} www.apple.com (苹果官网)"
    echo -e "${GREEN}2.${NC} dash.cloudflare.com (Cloudflare)"
    echo -e "${GREEN}3.${NC} www.bing.com (微软必应)"
    echo -e "${GREEN}4.${NC} www.microsoft.com (微软官网)"
    echo -e "${GREEN}5.${NC} itunes.apple.com (苹果 iTunes)"
    echo -e "${GREEN}6.${NC} gateways.icloud.com (苹果 iCloud)"
    echo -e "${GREEN}7.${NC} cloud.tencent.com (腾讯云)"
    echo -e "${GREEN}8.${NC} 自定义输入域名"
    echo -e "${GREEN}0.${NC} 返回上一级"
    read -p "请输入选项 [0-8] (也可直接输入域名): " sni_choice
    case $sni_choice in
        1) NEW_SNI="www.apple.com" ;;
        2) NEW_SNI="dash.cloudflare.com" ;;
        3) NEW_SNI="www.bing.com" ;;
        4) NEW_SNI="www.microsoft.com" ;;
        5) NEW_SNI="itunes.apple.com" ;;
        6) NEW_SNI="gateways.icloud.com" ;;
        7) NEW_SNI="cloud.tencent.com" ;;
        8) read -p "请输入新的 SNI 域名: " NEW_SNI ;;
        0) return ;;
        *)
            if [[ -n "$sni_choice" ]]; then
                NEW_SNI="$sni_choice"
            else
                echo -e "${RED}[错误] 输入不能为空${NC}"
                return
            fi
            ;;
    esac
    NEW_SNI=$(echo "$NEW_SNI" | sed -e 's|^https\?://||' -e 's|/.*$||' -e 's| ||g')
    if [ -z "$NEW_SNI" ]; then
        echo -e "${RED}[错误] 无效的 SNI 域名${NC}"
        return
    fi
    if command -v jq >/dev/null 2>&1; then
        local cur_port=$(jq -r '.inbounds[0].port // 443' /usr/local/etc/xray/config.json 2>/dev/null)
        jq --arg sni "$NEW_SNI" --arg dest "$NEW_SNI:${cur_port:-443}" '.inbounds[0].streamSettings.realitySettings.serverNames = [$sni] | .inbounds[0].streamSettings.realitySettings.dest = $dest' /usr/local/etc/xray/config.json > /usr/local/etc/xray/config.json.tmp && mv /usr/local/etc/xray/config.json.tmp /usr/local/etc/xray/config.json
    else
        sed -i "s/\"dest\": \"[^\"]*:\([0-9]*\)\"/\"dest\": \"$NEW_SNI:\1\"/" /usr/local/etc/xray/config.json
        if grep -q '"serverNames"[^[]*\[ *"[^"]*"' /usr/local/etc/xray/config.json; then
            sed -i 's/\("serverNames"[^[]*\[ *"\)[^"]*/\1'"$NEW_SNI"'/' /usr/local/etc/xray/config.json
        else
            sed -i '/"serverNames"/,/\]/{ /"serverNames"/!s/"[^"]*"/"'"$NEW_SNI"'"/ }' /usr/local/etc/xray/config.json
        fi
    fi
    restart_services
    log_success "SNI已修改为: $NEW_SNI"
    show_xray_link
}
show_xray_link() {
    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo -e "${RED}[错误] 未检测到 Xray 配置文件，请先安装 Xray${NC}"
        return
    fi
    if command -v jq >/dev/null 2>&1; then
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id' /usr/local/etc/xray/config.json)
        FLOW=$(jq -r '.inbounds[0].settings.clients[0].flow' /usr/local/etc/xray/config.json)
        SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /usr/local/etc/xray/config.json)
        SHORTID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' /usr/local/etc/xray/config.json)
        PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' /usr/local/etc/xray/config.json)
        PORT=$(jq -r '.inbounds[0].port' /usr/local/etc/xray/config.json)
        NET=$(jq -r '.inbounds[0].streamSettings.network' /usr/local/etc/xray/config.json)
    else
        UUID=$(grep -oP '"id": *"\K[^"]+' /usr/local/etc/xray/config.json)
        FLOW=$(grep -oP '"flow": *"\K[^"]+' /usr/local/etc/xray/config.json)
        SNI=$(get_xray_sni)
        SHORTID=$(get_xray_shortid)
        PRIVATE_KEY=$(grep -oP '"privateKey": *"\K[^"]+' /usr/local/etc/xray/config.json)
        PORT=$(grep -oP '"port": *\K[0-9]+' /usr/local/etc/xray/config.json | head -1)
        NET=$(grep -oP '"network": *"\K[^"]+' /usr/local/etc/xray/config.json)
    fi
    if [ -z "$SNI" ] || [ "$SNI" = "null" ]; then
        SNI=$(get_xray_sni)
    fi
    PUBLIC_KEY="n5cQsnGAxadThor3_U5fIFafC24rA0-OrA3vQj06onU"
    DOMAIN=$(curl -s ifconfig.me)
    REGION="$(curl -s "https://ipinfo.io/$DOMAIN/country")"
    REGION_CN=${COUNTRY_MAP[$REGION]}
    [ -z "$REGION_CN" ] && REGION_CN="$REGION"
    LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=$FLOW&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORTID&type=$NET#$REGION_CN"
    echo -e "\n${YELLOW}>>> 当前Xray Reality分享链接：${NC}"
    echo -e "${GREEN}$LINK${NC}\n"
}
check_and_uninstall() {
    local has_installed=false
    if [ -f /etc/systemd/system/frps.service ] || [ -d /usr/local/frp ] || [ -d /etc/frp ] || systemctl is-active --quiet frps 2>/dev/null; then
        has_installed=true
    fi
    if [ -f /etc/systemd/system/xray.service ] || [ -f /usr/local/bin/xray ] || [ -d /usr/local/etc/xray ] || systemctl is-active --quiet xray 2>/dev/null; then
        has_installed=true
    fi
    if [ "$has_installed" = true ]; then
        uninstall_frps
        uninstall_xray
        log_success "旧版本卸载完成，准备开始全新安装"
    fi
}
show_menu() {
    echo -e "${YELLOW}=== Xray & FRPS 管理脚本 ===${NC}"
    echo -e "${GREEN}1.${NC} 安装 Xray + FRPS"
    echo -e "${GREEN}2.${NC} 卸载 Xray + FRPS"
    echo -e "${GREEN}3.${NC} 卸载 FRPS"
    echo -e "${GREEN}4.${NC} 修改Xray端口"
    echo -e "${GREEN}5.${NC} 修改SHORTID密钥"
    echo -e "${GREEN}6.${NC} 修改Xray SNI"
    echo -e "${GREEN}7.${NC} 查看Xray分享链接"
    echo -e "${GREEN}8.${NC} 退出"
    echo -e "${YELLOW}===========================${NC}"
}
main() {
    check_root
    while true; do
        show_menu
        read -p "请选择操作 [1-8]: " choice
        case $choice in
            1)
                check_and_uninstall
                install_dependencies
                install_frps
                install_xray
                cleanup
                show_results
                ;;
            2)
                uninstall_frps
                uninstall_xray
                log_success "所有服务已卸载"
                ;;
            3)
                uninstall_frps
                log_success "FRPS 服务已卸载"
                ;;
            4)
                modify_xray_port
                ;;
            5)
                modify_xray_shortid
                ;;
            6)
                modify_xray_sni
                ;;
            7)
                show_xray_link
                ;;
            8)
                echo -e "${GREEN}退出脚本${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重试${NC}"
                ;;
        esac
    done
}
main
