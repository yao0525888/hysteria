#!/usr/bin/env bash
set -euo pipefail

XUI_PORT=7008
XUI_USER="admin"
XUI_PASS="yao581581"
XUI_BIN_URL="https://github.com/vaxilu/x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz"
XUI_BIN_URL_BACKUP="https://gitee.com/yao0525888/amd/releases/download/v2/x-ui-linux-amd64.tar.gz"
LOCAL_TAR="/root/x-ui-linux-amd64.tar.gz"
INSTALL_DIR="/usr/local/x-ui"
APP_DIR="${INSTALL_DIR}/x-ui"
BIN_PATH="${APP_DIR}/x-ui"
SERVICE_NAME="x-ui"
GREEN="$(printf '\033[32m')"
RESET="$(printf '\033[0m')"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "请用 root 运行"; exit 1; }; }
ok() { :; }
fail() { echo -e "[ERR] $*" >&2; exit 1; }

install_xui() {
  need_root
  if command -v apt >/dev/null 2>&1; then
    apt update >/dev/null 2>&1
    apt install -y curl wget tar >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release >/dev/null 2>&1
    yum install -y curl wget tar >/dev/null 2>&1
  else
    fail "未检测到 apt 或 yum，请手动安装 curl/wget/tar"
  fi
  ok "依赖安装完成"

  rm -rf "$APP_DIR"
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  tmp_tar="/tmp/x-ui.tar.gz"
  if [ -f "$LOCAL_TAR" ]; then
    cp "$LOCAL_TAR" "$tmp_tar"
  else
    if ! wget -q -O "$tmp_tar" "$XUI_BIN_URL"; then
      wget -q -O "$tmp_tar" "$XUI_BIN_URL_BACKUP" || fail "下载 x-ui 失败"
    fi
  fi
  tar -xzf "$tmp_tar" -C "$INSTALL_DIR" >/dev/null 2>&1
  chmod +x "${BIN_PATH}"
  ok "x-ui 下载并解压完成"

  cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=x-ui service
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
ExecStart=${BIN_PATH}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
  ok "systemd 服务创建完成"

  systemctl restart ${SERVICE_NAME} >/dev/null 2>&1
  sleep 2
  if ! systemctl is-active --quiet ${SERVICE_NAME}; then
    echo "[ERR] 服务启动失败，最近日志："
    journalctl -u ${SERVICE_NAME} -n 40 --no-pager || true
    fail "请根据日志修复后重试"
  fi
  ok "服务已启动"

  ${BIN_PATH} setting -port ${XUI_PORT} -username "${XUI_USER}" -password "${XUI_PASS}" >/dev/null 2>&1
  systemctl restart ${SERVICE_NAME} >/dev/null 2>&1
  ok "账号与端口已配置：${XUI_USER}/${XUI_PASS} @ ${XUI_PORT}"

  PUBLIC_IP="$(curl -4 -s https://api.ipify.org || curl -s https://ifconfig.me || echo "未获取公网IP")"
  cat <<INFO
x-ui 已安装并运行
面板地址: ${GREEN}http://${PUBLIC_IP}:${XUI_PORT}${RESET}
用户名: ${GREEN}${XUI_USER}${RESET}
密码: ${GREEN}${XUI_PASS}${RESET}

INFO
}

uninstall_xui() {
  need_root
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    systemctl stop ${SERVICE_NAME} || true
    systemctl disable ${SERVICE_NAME} || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload
  fi
  rm -rf "${INSTALL_DIR}"
  rm -f /tmp/x-ui.tar.gz
  ok "x-ui 已卸载"
}

add_socks() {
  need_root
  curl -s -X POST -d "username=${XUI_USER}&password=${XUI_PASS}" -c /tmp/cookie.txt "http://127.0.0.1:${XUI_PORT}/login" >/dev/null
  local settings='{"auth":"password","accounts":[{"user":"admin","pass":"admin"}],"udp":true}'
  local streamSettings='{"network":"tcp","security":"none","tcpSettings":{"header":{"type":"none"}}}'
  local sniffing='{"enabled":true,"destOverride":["http","tls"]}'
  local res=$(curl -s -X POST -b /tmp/cookie.txt -d "up=0" -d "down=0" -d "total=0" -d "remark=socks" -d "enable=true" -d "expiryTime=0" -d "listen=" -d "port=7009" -d "protocol=socks" -d "settings=${settings}" -d "streamSettings=${streamSettings}" -d "sniffing=${sniffing}" "http://127.0.0.1:${XUI_PORT}/xui/inbound/add")
  rm -f /tmp/cookie.txt
  if [[ "$res" == *"true"* ]]; then
    PUBLIC_IP="$(curl -4 -s https://api.ipify.org || curl -s https://ifconfig.me || echo "未获取公网IP")"
    cat <<INFO
Socks配置成功
地址: ${GREEN}${PUBLIC_IP}${RESET}
端口: ${GREEN}7009${RESET}
用户: ${GREEN}admin${RESET}
密码: ${GREEN}admin${RESET}
INFO
  else
    fail "配置失败: $res"
  fi
}

menu() {
  echo "1) 安装 x-ui"
  echo "2) 卸载 x-ui"
  echo "3) 一键配置socks"
  read -rp "选择操作 [1/2/3]: " c
  case "$c" in
    1|"") install_xui ;;
    2) uninstall_xui ;;
    3) add_socks ;;
    *) echo "无效选择"; exit 1 ;;
  esac
}

case "${1:-}" in
  install) install_xui ;;
  uninstall) uninstall_xui ;;
  socks) add_socks ;;
  *) menu ;;
esac