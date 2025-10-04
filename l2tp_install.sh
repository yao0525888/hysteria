#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

log() { echo -e "[l2tp] $*"; }
die() { echo -e "[l2tp][error] $*" >&2; exit 1; }

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "必须以root运行。请使用 sudo."; }

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID=${ID:-}
    OS_VER_ID=${VERSION_ID:-}
  else
    die "无法检测系统: 缺少 /etc/os-release"
  fi
}

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
  else
    die "未找到受支持的包管理器 (apt/dnf/yum)"
  fi
}

random_string() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
}

get_default_interface() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

get_public_ip() {
  curl -fsS --max-time 5 ifconfig.me 2>/dev/null || curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true
}

setup_china_mirror() {
  local use_mirror="${USE_CHINA_MIRROR:-auto}"
  
  if [[ ${use_mirror} == "no" ]]; then
    return 0
  fi
  
  if [[ ${use_mirror} == "auto" ]]; then
    local server_location
    server_location=$(curl -fsS --max-time 3 https://ipapi.co/country_code 2>/dev/null || echo "")
    if [[ ${server_location} != "CN" ]]; then
      return 0
    fi
  fi
  
  log "检测到国内服务器，配置国内镜像源..."
  
  case "${PKG_MGR}" in
    apt)
      if [[ -f /etc/apt/sources.list ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s) 2>/dev/null || true
        local codename
        codename=$(grep VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
        if [[ -z ${codename} ]]; then
          codename=$(cat /etc/os-release | grep -oP 'VERSION="\K[^"]+' | awk '{print $1}' | tr '[:upper:]' '[:lower:]' || echo "bookworm")
        fi
        
        local is_debian=0
        if [[ -f /etc/debian_version ]] && [[ ${OS_ID} == "debian" || ! ${OS_ID} == "ubuntu" ]]; then
          is_debian=1
        fi
        
        if [[ ${is_debian} -eq 1 ]]; then
          log "配置 Debian ${codename} 阿里云镜像源"
          cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/debian/ ${codename} main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian-security/ ${codename}-security main contrib non-free non-free-firmware
EOF
        else
          log "配置 Ubuntu ${codename} 阿里云镜像源"
          cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/ubuntu/ ${codename} main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${codename}-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${codename}-backports main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${codename}-security main restricted universe multiverse
EOF
        fi
        log "已切换到阿里云镜像源，更新索引..."
        apt-get update -y
      fi
      ;;
    yum|dnf)
      if [[ ! -f /etc/yum.repos.d/CentOS-Base.repo.bak ]]; then
        cp -f /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak 2>/dev/null || true
      fi
      if grep -q "mirrors.aliyun.com" /etc/yum.repos.d/*.repo 2>/dev/null; then
        log "已使用阿里云镜像，跳过"
        return 0
      fi
      local ver="${OS_VER_ID%%.*}"
      if [[ ${PKG_MGR} == "yum" ]] && [[ -n ${ver} ]]; then
        curl -fsSL -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-${ver}.repo 2>/dev/null || true
        ${PKG_MGR} clean all >/dev/null 2>&1 || true
        log "已切换到阿里云镜像源"
      fi
      ;;
  esac
}

ensure_epel_if_needed() {
  if [[ ${PKG_MGR} == "yum" || ${PKG_MGR} == "dnf" ]]; then
    if [[ -n ${OS_VER_ID:-} ]] && [[ ${OS_VER_ID%%.*} -le 7 ]]; then
      if ! rpm -qa | grep -qi epel-release; then
        log "安装 EPEL 仓库..."
        if [[ ${PKG_MGR} == "dnf" ]]; then
          dnf -y install epel-release || true
        else
          yum -y install epel-release || true
        fi
      fi
    fi
  fi
}

install_packages() {
  log "安装依赖 (strongswan/libreswan, xl2tpd, ppp, iptables)..."
  case "${PKG_MGR}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      log "尝试安装 strongswan 和 xl2tpd..."
      if apt-get install -y --no-install-recommends strongswan strongswan-pki libstrongswan-standard-plugins xl2tpd ppp iptables curl 2>&1; then
        log "strongswan 安装成功"
      else
        log "strongswan 安装失败，尝试 libreswan..."
        apt-get install -y --no-install-recommends libreswan xl2tpd ppp iptables curl 2>&1 || {
          log "libreswan 也失败，尝试最小安装..."
          apt-get install -y strongswan xl2tpd ppp iptables curl 2>&1 || true
        }
      fi
      ;;
    dnf)
      dnf -y install libreswan xl2tpd ppp iptables curl
      ;;
    yum)
      yum -y install libreswan xl2tpd ppp iptables curl || true
      ;;
  esac
  
  if ! command -v ipsec >/dev/null 2>&1; then
    die "IPsec 软件安装失败。请手动运行: apt-get install -y strongswan xl2tpd"
  fi
  if ! command -v xl2tpd >/dev/null 2>&1; then
    die "xl2tpd 安装失败。请手动运行: apt-get install -y xl2tpd"
  fi
  log "依赖包安装完成 ✓"
}

write_sysctl() {
  cat >/etc/sysctl.d/99-l2tp-ipsec.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-l2tp-ipsec.conf || true
}

write_ipsec_config() {
  local public_ip="$1"
  cat >/etc/ipsec.conf <<'EOF'
config setup
  uniqueids=no
  protostack=netkey

include /etc/ipsec.d/*.conf
EOF

  cat >/etc/ipsec.d/l2tp-ipsec.conf <<EOF
conn l2tp-psk
  type=transport
  authby=secret
  ike=aes256-sha1,aes128-sha1,3des-sha1
  phase2=esp
  phase2alg=aes256-sha1,aes128-sha1,3des-sha1
  pfs=no
  rekey=no
  keyingtries=3
  dpddelay=30
  dpdtimeout=120
  dpdaction=clear
  left=%defaultroute
  leftid=${public_ip}
  leftprotoport=17/1701
  right=%any
  rightprotoport=17/%any
  ikev2=no
  auto=add
EOF
}

write_ipsec_secrets() {
  local psk="$1"
  umask 077
  cat >/etc/ipsec.secrets <<EOF
%any  %any  : PSK "${psk}"
EOF
}

write_xl2tpd() {
  local local_ip="$1"; shift
  local pool_start="$1"; shift
  local pool_end="$1"; shift
  local pppoptfile="/etc/ppp/options.xl2tpd"

  mkdir -p /etc/xl2tpd
  cat >/etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes

[lns default]
ip range = ${pool_start}-${pool_end}
local ip = ${local_ip}
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = no
pppoptfile = ${pppoptfile}
length bit = yes
EOF

  mkdir -p /etc/ppp
  cat >"${pppoptfile}" <<'EOF'
name l2tpd
ipcp-accept-local
ipcp-accept-remote
ms-dns 1.1.1.1
ms-dns 8.8.8.8
noccp
auth
crtscts
idle 1800
mtu 1400
mru 1400
lock
hide-password
local
debug
modem
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
connect-delay 5000
EOF
}

write_chap_secrets() {
  local user="$1"; local pass="$2"
  umask 077
  cat >/etc/ppp/chap-secrets <<EOF
"${user}"  l2tpd  "${pass}"  *
EOF
}

create_fw_script() {
  local vpn_subnet="$1"; local public_if="$2"
  local script_path="/usr/local/sbin/l2tp-iptables.sh"
  cat >"${script_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

iptables -C INPUT -p udp --dport 500 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -C INPUT -p udp --dport 4500 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -C INPUT -p udp --dport 1701 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 1701 -j ACCEPT

iptables -C FORWARD -s ${vpn_subnet} -o ${public_if} -j ACCEPT 2>/dev/null || iptables -A FORWARD -s ${vpn_subnet} -o ${public_if} -j ACCEPT
iptables -C FORWARD -d ${vpn_subnet} -m conntrack --ctstate ESTABLISHED,RELATED -i ${public_if} -j ACCEPT 2>/dev/null || iptables -A FORWARD -d ${vpn_subnet} -m conntrack --ctstate ESTABLISHED,RELATED -i ${public_if} -j ACCEPT

iptables -t nat -C POSTROUTING -s ${vpn_subnet} -o ${public_if} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${vpn_subnet} -o ${public_if} -j MASQUERADE
EOF
  chmod +x "${script_path}"

  cat >/etc/systemd/system/l2tp-iptables.service <<EOF
[Unit]
Description=Apply iptables rules for L2TP/IPsec
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${script_path}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now l2tp-iptables.service || true
}

restart_services() {
  systemctl enable ipsec xl2tpd >/dev/null 2>&1 || true
  systemctl restart ipsec || true
  sleep 2
  systemctl restart xl2tpd || true
}

show_creds() {
  local psk user pass
  psk=$(awk '/PSK/ {match($0,/\"(.*)\"/,a); print a[1]}' /etc/ipsec.secrets 2>/dev/null || true)
  user=$(awk 'NR==1 {gsub(/\"/,"",$1); print $1}' /etc/ppp/chap-secrets 2>/dev/null || true)
  pass=$(awk 'NR==1 {gsub(/\"/,"",$3); print $3}' /etc/ppp/chap-secrets 2>/dev/null || true)
  local server_ip
  server_ip=$(get_public_ip)
  echo "================ VPN 凭据 ================"
  echo "服务器: ${server_ip:-<你的服务器公网IP>}"
  echo "IPSec PSK: ${psk:-<未知>}"
  echo "用户名: ${user:-<未知>}"
  echo "密码: ${pass:-<未知>}"
  echo "========================================="
}

if [[ ${1:-} == "--show-creds" ]]; then
  require_root
  show_creds
  exit 0
fi

require_root
detect_os
detect_pkg_mgr
setup_china_mirror
ensure_epel_if_needed

IPSEC_PSK="${IPSEC_PSK:-}"
VPN_USER="${VPN_USER:-}"
VPN_PASSWORD="${VPN_PASSWORD:-}"
VPN_SUBNET="${VPN_SUBNET:-10.10.0.0/24}"
VPN_LOCAL_IP="${VPN_LOCAL_IP:-10.10.0.1}"
VPN_POOL_START="${VPN_POOL_START:-10.10.0.10}"
VPN_POOL_END="${VPN_POOL_END:-10.10.0.200}"

[[ -n ${IPSEC_PSK} ]] || IPSEC_PSK="$(random_string)"
[[ -n ${VPN_USER} ]] || VPN_USER="vpnuser"
[[ -n ${VPN_PASSWORD} ]] || VPN_PASSWORD="$(random_string)"

PUBLIC_IF="$(get_default_interface)"
[[ -n ${PUBLIC_IF} ]] || die "无法检测默认出口网卡。请设置环境变量 PUBLIC_IF 后重试"
PUBLIC_IP="$(get_public_ip)"

install_packages
write_sysctl
write_ipsec_config "${PUBLIC_IP:-%defaultroute}"
write_ipsec_secrets "${IPSEC_PSK}"
write_xl2tpd "${VPN_LOCAL_IP}" "${VPN_POOL_START}" "${VPN_POOL_END}"
write_chap_secrets "${VPN_USER}" "${VPN_PASSWORD}"
create_fw_script "${VPN_SUBNET}" "${PUBLIC_IF}"
restart_services

log "安装完成。"
show_creds
echo "配置文件: /etc/ipsec.conf, /etc/ipsec.d/l2tp-ipsec.conf, /etc/ipsec.secrets, /etc/xl2tpd/xl2tpd.conf, /etc/ppp/options.xl2tpd, /etc/ppp/chap-secrets"
echo "防火墙规则服务: l2tp-iptables.service (systemd)"
echo "如需修改DNS或地址池，请编辑 /etc/xl2tpd/xl2tpd.conf 与 /etc/ppp/options.xl2tpd 后重启: systemctl restart xl2tpd"


