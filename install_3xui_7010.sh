#!/usr/bin/env bash

set -e

PANEL_PORT=7010
USERNAME="admin"
PASSWORD="admin"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 用户运行此脚本：sudo bash $0"
  exit 1
fi

install_panel() {
  echo "正在安装 3x-ui 面板，请稍候..."

  if ! command -v apt >/dev/null 2>&1; then
    echo "错误：当前系统不是基于 Debian/Ubuntu"
    exit 1
  fi

  apt update -y >/dev/null 2>&1
  apt install -y curl socat sqlite3 >/dev/null 2>&1

  printf "y\n%s\n" "$PANEL_PORT" | bash <(curl -Ls "$INSTALL_SCRIPT_URL") >/dev/null 2>&1

  BIN_CANDIDATES=(
    "3x-ui"
    "/usr/local/3x-ui/3x-ui"
    "/usr/bin/3x-ui"
    "/usr/local/x-ui/x-ui"
    "x-ui"
  )

  XUI_BIN=""
  for bin in "${BIN_CANDIDATES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
      XUI_BIN="$bin"
      break
    fi
  done

  if [ -z "$XUI_BIN" ]; then
    echo "错误：未找到 x-ui 可执行文件"
    return 1
  fi

  "$XUI_BIN" setting -port "$PANEL_PORT" >/dev/null 2>&1 || true
  "$XUI_BIN" setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true
  
  DB_FILE="/etc/x-ui/x-ui.db"
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/x-ui/bin/x-ui.db"
  fi
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/3x-ui/bin/x-ui.db"
  fi

  "$XUI_BIN" setting -webBasePath / >/dev/null 2>&1 || "$XUI_BIN" setting -webPath / >/dev/null 2>&1 || true

  if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$DB_FILE" "UPDATE setting SET value = '/' WHERE key = 'webBasePath';" >/dev/null 2>&1 || \
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO setting (key, value) VALUES ('webBasePath', '/');" >/dev/null 2>&1 || true
    
    WEB_PATH=$(sqlite3 "$DB_FILE" "SELECT value FROM setting WHERE key = 'webBasePath';" 2>/dev/null || echo "")
    if [ "$WEB_PATH" != "/" ]; then
      sqlite3 "$DB_FILE" "DELETE FROM setting WHERE key = 'webBasePath'; INSERT INTO setting (key, value) VALUES ('webBasePath', '/');" >/dev/null 2>&1 || true
    fi
  fi

  systemctl restart x-ui >/dev/null 2>&1 || service x-ui restart >/dev/null 2>&1 || "$XUI_BIN" restart >/dev/null 2>&1 || true
  sleep 3

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PANEL_PORT}"/tcp >/dev/null 2>&1 || true
  fi

  echo ""
  echo "==== 安装完成 ===="
  SERVER_IP=$(curl -4s https://api.ipify.org 2>/dev/null || curl -4s https://ifconfig.me 2>/dev/null || echo "<你的公网IP>")

  echo -e "面板地址：\033[0;32mhttp://$SERVER_IP:$PANEL_PORT/\033[0m"
  echo ""
  echo "用户名：$USERNAME"
  echo "密  码：$PASSWORD"
}

reset_account() {
  echo "==== 重置面板账号密码 ===="
  
  BIN_CANDIDATES=(
    "3x-ui"
    "/usr/local/3x-ui/3x-ui"
    "/usr/bin/3x-ui"
    "/usr/local/x-ui/x-ui"
    "x-ui"
  )

  XUI_BIN=""
  for bin in "${BIN_CANDIDATES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
      XUI_BIN="$bin"
      break
    fi
  done

  if [ -z "$XUI_BIN" ]; then
    echo "未找到 x-ui 可执行文件，请先安装面板。"
    return 1
  fi

  NEW_USERNAME="admin"
  NEW_PASSWORD="admin"
  echo "重置为：用户名=admin, 密码=admin"

  echo "通过命令行设置账号密码..."
  SET_RESULT=$("$XUI_BIN" setting -username "$NEW_USERNAME" -password "$NEW_PASSWORD" 2>&1)
  echo "$SET_RESULT"

  DB_FILE="/etc/x-ui/x-ui.db"
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/x-ui/bin/x-ui.db"
  fi
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/3x-ui/bin/x-ui.db"
  fi

  if [ -f "$DB_FILE" ]; then
    if ! command -v sqlite3 >/dev/null 2>&1; then
      echo "安装 sqlite3 工具..."
      apt update -y && apt install -y sqlite3 2>/dev/null || true
    fi
    
    if command -v sqlite3 >/dev/null 2>&1; then
      echo "设置面板路径为根目录..."
      sqlite3 "$DB_FILE" "UPDATE setting SET value = '/' WHERE key = 'webBasePath';" 2>/dev/null || \
      sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO setting (key, value) VALUES ('webBasePath', '/');" 2>/dev/null || true
    fi
  fi

  echo "重启 x-ui 服务..."
  systemctl restart x-ui 2>/dev/null || service x-ui restart 2>/dev/null || "$XUI_BIN" restart 2>/dev/null || true
  sleep 2

  echo "==== 重置完成 ===="
  SERVER_IP=$(curl -4s https://api.ipify.org || curl -4s https://ifconfig.me || echo "<你的公网IP>")
  echo -e "面板地址：\033[0;32mhttp://$SERVER_IP:7010/\033[0m"
  echo "用户名：$NEW_USERNAME"
  echo "密码：$NEW_PASSWORD"
}

uninstall_panel() {
  echo "==== 卸载 3x-ui 面板 ===="

  if command -v x-ui >/dev/null 2>&1; then
    x-ui uninstall
  elif command -v 3x-ui >/dev/null 2>&1; then
    3x-ui uninstall
  elif [ -x /usr/local/x-ui/x-ui ]; then
    /usr/local/x-ui/x-ui uninstall
  elif [ -x /usr/local/3x-ui/3x-ui ]; then
    /usr/local/3x-ui/3x-ui uninstall
  else
    echo "未找到 x-ui / 3x-ui 可执行文件，可能尚未安装。"
  fi
}

echo "====== 3x-ui 管理脚本 ======"
echo "1) 安装面板"
echo "2) 卸载面板"
echo "3) 重置账号密码"
echo "0) 退出"
read -rp "请输入选项[1/2/3/0]: " choice

case "$choice" in
  1) install_panel ;;
  2) uninstall_panel ;;
  3) reset_account ;;
  0) echo "已退出"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac

