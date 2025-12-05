#!/usr/bin/env bash
set -euo pipefail

XUI_PORT=7008
XUI_USER="admin"
XUI_PASS="yao581581"
XUI_BIN_URL="https://github.com/vaxilu/x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz"
INSTALL_DIR="/usr/local/x-ui"
APP_DIR="${INSTALL_DIR}/x-ui"
BIN_PATH="${APP_DIR}/x-ui"
SERVICE_NAME="x-ui"
GREEN="$(printf '\033[32m')"
RESET="$(printf '\033[0m')"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "请用 root 运行"; exit 1; }; }
ok() { echo -e "[OK] $*"; }
fail() { echo -e "[ERR] $*" >&2; exit 1; }

install_xui() {
  need_root
  if command -v apt >/dev/null 2>&1; then
    apt update
    apt install -y curl wget tar
  elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release
    yum install -y curl wget tar
  else
    fail "未检测到 apt 或 yum，请手动安装 curl/wget/tar"
  fi
  ok "依赖安装完成"

  rm -rf "$APP_DIR"
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  tmp_tar="/tmp/x-ui.tar.gz"
  wget -O "$tmp_tar" "$XUI_BIN_URL"
  tar -xzf "$tmp_tar" -C "$INSTALL_DIR"
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
  systemctl enable ${SERVICE_NAME}
  ok "systemd 服务创建完成"

  systemctl restart ${SERVICE_NAME}
  sleep 2
  if ! systemctl is-active --quiet ${SERVICE_NAME}; then
    echo "[ERR] 服务启动失败，最近日志："
    journalctl -u ${SERVICE_NAME} -n 40 --no-pager || true
    fail "请根据日志修复后重试"
  fi
  ok "服务已启动"

  ${BIN_PATH} setting -port ${XUI_PORT} -username "${XUI_USER}" -password "${XUI_PASS}"
  systemctl restart ${SERVICE_NAME}
  ok "账号与端口已配置：${XUI_USER}/${XUI_PASS} @ ${XUI_PORT}"

  PUBLIC_IP="$(curl -4 -s https://api.ipify.org || curl -s https://ifconfig.me || echo "未获取公网IP")"
  cat <<INFO
-----------------------------
x-ui 已安装并运行
面板地址: ${GREEN}http://${PUBLIC_IP}:${XUI_PORT}${RESET}
用户名: ${GREEN}${XUI_USER}${RESET}
密码: ${GREEN}${XUI_PASS}${RESET}
服务管理: systemctl {start|stop|restart|status} ${SERVICE_NAME}
文件路径: ${INSTALL_DIR}
-----------------------------
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

menu() {
  echo "1) 安装 x-ui"
  echo "2) 卸载 x-ui"
  read -rp "选择操作 [1/2]: " c
  case "$c" in
    1|"") install_xui ;;
    2) uninstall_xui ;;
    *) echo "无效选择"; exit 1 ;;
  esac
}

case "${1:-}" in
  install) install_xui ;;
  uninstall) uninstall_xui ;;
  *) menu ;;
esac
