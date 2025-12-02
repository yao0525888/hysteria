#!/bin/bash

set -e

PROJECT_DIR="/opt/pi-network"

show_menu() {
    clear
    echo "========================================="
    echo "  Pi Network 后端管理"
    echo "========================================="
    echo ""
    echo "请选择操作："
    echo "  1) 安装后端服务"
    echo "  2) 修改 API Key"
    echo "  3) 查看当前配置"
    echo "  4) 卸载后端服务"
    echo "  5) 退出"
    echo ""
    echo -n "请输入选项 [1-5]: "
    read -r choice
    
    case "$choice" in
        1) install_backend ;;
        2) change_api_key ;;
        3) show_config ;;
        4) uninstall_backend ;;
        5) echo "退出"; exit 0 ;;
        *) echo "无效选项"; sleep 2; show_menu ;;
    esac
}

change_api_key() {
    clear
    echo "========================================="
    echo "  修改 API Key"
    echo "========================================="
    echo ""
    
    if [ ! -f "$PROJECT_DIR/backend/.env" ]; then
        echo "✗ 后端服务未安装"
        echo "请先安装后端服务"
        sleep 3
        show_menu
        return
    fi
    
    echo "当前 API Key:"
    OLD_API_KEY=$(grep "^API_KEY=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    echo "$OLD_API_KEY"
    echo ""
    echo -n "请输入新的 API Key (直接回车生成随机): "
    read -r NEW_API_KEY
    
    if [ -z "$NEW_API_KEY" ]; then
        NEW_API_KEY=$(openssl rand -hex 32)
        echo "已生成随机 API Key: $NEW_API_KEY"
    fi
    
    echo ""
    echo -n "确认修改 API Key？(y/n): "
    read -r confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        sed -i "s/^API_KEY=.*/API_KEY=$NEW_API_KEY/" $PROJECT_DIR/backend/.env
        echo "$NEW_API_KEY" > /root/pi-network-api-key.txt
        
        systemctl restart pi-network-backend
        
        echo ""
        echo "✓ API Key 已更新"
        echo "✓ 后端服务已重启"
        echo "✓ API Key 已保存到: /root/pi-network-api-key.txt"
        echo ""
        echo "新的 API Key: $NEW_API_KEY"
        echo ""
        echo "请更新客户端脚本中的 API_KEY 变量"
    else
        echo "已取消"
    fi
    
    echo ""
    echo -n "按回车键继续..."
    read
    show_menu
}

uninstall_backend() {
    clear
    echo "========================================="
    echo "  卸载后端服务"
    echo "========================================="
    echo ""
    
    if [ ! -f "$PROJECT_DIR/backend/.env" ]; then
        echo "✗ 后端服务未安装"
        sleep 3
        show_menu
        return
    fi
    
    echo "警告: 此操作将删除以下内容："
    echo "  • 后端服务"
    echo "  • 项目文件 ($PROJECT_DIR)"
    echo "  • systemd 服务配置"
    echo ""
    echo -n "确认卸载？(y/n): "
    read -r confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        echo ">>> 停止服务..."
        systemctl stop pi-network-backend 2>/dev/null
        systemctl disable pi-network-backend 2>/dev/null
        echo "✓ 服务已停止"
        
        echo ""
        echo ">>> 删除服务配置..."
        rm -f /etc/systemd/system/pi-network-backend.service
        systemctl daemon-reload
        echo "✓ 服务配置已删除"
        
        echo ""
        echo ">>> 删除项目文件..."
        rm -rf $PROJECT_DIR
        echo "✓ 项目文件已删除"
        
        echo ""
        echo ">>> 清理防火墙规则..."
        if command -v ufw &> /dev/null; then
            ufw delete allow 7008/tcp 2>/dev/null && echo "✓ UFW 规则已删除"
        elif command -v firewall-cmd &> /dev/null; then
            firewall-cmd --permanent --remove-port=7008/tcp 2>/dev/null
            firewall-cmd --reload 2>/dev/null
            echo "✓ firewalld 规则已删除"
        fi
        
        echo ""
        echo "✓ 卸载完成"
        echo ""
        echo "注意: API Key 备份文件保留在 /root/pi-network-api-key.txt"
    else
        echo "已取消"
    fi
    
    echo ""
    echo -n "按回车键继续..."
    read
    show_menu
}

show_config() {
    clear
    echo "========================================="
    echo "  当前配置信息"
    echo "========================================="
    echo ""
    
    if [ ! -f "$PROJECT_DIR/backend/.env" ]; then
        echo "✗ 后端服务未安装"
        sleep 3
        show_menu
        return
    fi
    
    API_KEY=$(grep "^API_KEY=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    PORT=$(grep "^PORT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    ENABLE_LIMIT=$(grep "^ENABLE_LIMIT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    
    # Hysteria 2 配置
    HYSTERIA_PORT=$(grep "^HYSTERIA_PORT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    HYSTERIA_PASSWORD=$(grep "^HYSTERIA_PASSWORD=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    HYSTERIA_MASQUERADE_HOST=$(grep "^HYSTERIA_MASQUERADE_HOST=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    
    # Xray 配置
    XRAY_VERSION=$(grep "^XRAY_VERSION=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    XRAY_FRP_PORT=$(grep "^XRAY_FRP_PORT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    XRAY_FRP_TOKEN=$(grep "^XRAY_FRP_TOKEN=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    XRAY_PORT=$(grep "^XRAY_PORT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    XRAY_UUID=$(grep "^XRAY_UUID=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    XRAY_SNI=$(grep "^XRAY_SNI=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo "后端服务状态:"
    if systemctl is-active --quiet pi-network-backend; then
        echo "  ✓ 运行中"
    else
        echo "  ✗ 已停止"
    fi
    echo ""
    echo "配置信息:"
    echo "  后端地址: http://${SERVER_IP}:${PORT}"
    echo "  API Key: $API_KEY"
    echo "  项目目录: $PROJECT_DIR"
    echo "  限速开关: $ENABLE_LIMIT"
    echo ""
    echo "Hysteria 2 配置:"
    echo "  端口: $HYSTERIA_PORT"
    echo "  密码: $HYSTERIA_PASSWORD"
    echo "  伪装网站: $HYSTERIA_MASQUERADE_HOST"
    echo ""
    echo "Xray 配置:"
    echo "  Xray 版本: $XRAY_VERSION"
    echo "  Xray 端口: $XRAY_PORT"
    echo "  Xray UUID: $XRAY_UUID"
    echo "  Xray SNI: $XRAY_SNI"
    echo "  FRPS 端口: $XRAY_FRP_PORT"
    echo "  FRPS 密钥: $XRAY_FRP_TOKEN"
    echo ""
    echo "常用命令："
    echo "  查看状态: systemctl status pi-network-backend"
    echo "  查看日志: journalctl -u pi-network-backend -f"
    echo "  重启服务: systemctl restart pi-network-backend"
    echo ""
    
    echo -n "按回车键继续..."
    read
    show_menu
}

install_backend() {
    clear
    echo "========================================="
    echo "  Pi Network 后端一键安装"
    echo "========================================="
    echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 权限运行"
    exit 1
fi

echo ">>> 检查并卸载已存在的服务..."
if systemctl is-active --quiet pi-network-backend 2>/dev/null; then
    echo "发现已安装的后端服务，正在卸载..."
    systemctl stop pi-network-backend 2>/dev/null
    systemctl disable pi-network-backend 2>/dev/null
    rm -f /etc/systemd/system/pi-network-backend.service
    systemctl daemon-reload
    echo "✓ 旧服务已卸载"
fi

if [ -d "$PROJECT_DIR" ]; then
    echo "发现已存在的项目目录，正在清理..."
    rm -rf $PROJECT_DIR
    echo "✓ 旧项目文件已清理"
fi

DOWNLOAD_URL="https://github.com/yao0525888/hysteria/releases/download/v1/pi-network-backend.tar.gz"
TEMP_DIR="/tmp/pi-network-install"
PROJECT_DIR="/opt/pi-network"

echo ">>> 步骤 1/8: 安装必要工具..."
apt-get update -qq
apt-get install -y wget curl tar swaks

echo ""
echo ">>> 步骤 2/8: 下载项目文件..."
mkdir -p $TEMP_DIR
cd $TEMP_DIR

echo "正在从 GitHub 下载... (如果失败会自动重试)"
for i in {1..3}; do
    if wget -T 30 -t 3 --show-progress $DOWNLOAD_URL -O pi-network-backend.tar.gz; then
        echo "✓ 下载完成"
        break
    else
        if [ $i -lt 3 ]; then
            echo "下载失败，5秒后重试... ($i/3)"
            sleep 5
        else
            echo "✗ 下载失败，请检查网络连接或手动下载"
            echo "手动安装步骤："
            echo "1. 下载文件: $DOWNLOAD_URL"
            echo "2. 上传到服务器 /tmp/pi-network-backend.tar.gz"
            echo "3. 重新运行此脚本"
            exit 1
        fi
    fi
done

echo ""
echo ">>> 步骤 3/8: 解压文件..."
mkdir -p pi-network
tar -xzf pi-network-backend.tar.gz -C pi-network
if [ $? -ne 0 ]; then
    echo "✗ 解压失败"
    exit 1
fi
echo "✓ 解压完成"

echo ""
echo ">>> 步骤 4/8: 安装 Node.js..."
if ! command -v node &> /dev/null; then
    echo "正在安装 Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    echo "✓ Node.js 安装完成"
else
    echo "✓ Node.js 已安装 ($(node --version))"
fi

echo ""
echo ">>> 步骤 5/8: 复制文件到项目目录..."
mkdir -p $PROJECT_DIR
if [ -d "$TEMP_DIR/pi-network/backend" ]; then
    cp -r $TEMP_DIR/pi-network/* $PROJECT_DIR/
    echo "✓ 文件已复制到 $PROJECT_DIR"
else
    echo "✗ 找不到项目文件"
    ls -la $TEMP_DIR
    ls -la $TEMP_DIR/pi-network 2>/dev/null || true
    exit 1
fi

echo ""
echo ">>> 步骤 6/8: 安装依赖并配置..."
cd $PROJECT_DIR/backend
npm install --production

if [ ! -f .env ]; then
    DEFAULT_API_KEY=$(grep "^API_KEY=" env.example | cut -d'=' -f2)
    if [ -z "$DEFAULT_API_KEY" ]; then
        API_KEY=$(openssl rand -hex 32)
    else
        API_KEY="$DEFAULT_API_KEY"
    fi
    
    cp env.example .env
    sed -i "s/^API_KEY=.*/API_KEY=$API_KEY/" .env
    
    echo "✓ 配置文件已生成"
    echo ""
    echo "========================================="
    echo "  重要！请保存您的 API Key："
    echo "  $API_KEY"
    echo "========================================="
    echo ""
    
    echo "API_KEY=$API_KEY" > /root/pi-network-api-key.txt
    echo "API Key 也已保存到: /root/pi-network-api-key.txt"
else
    API_KEY=$(grep "^API_KEY=" .env | cut -d'=' -f2)
    echo "✓ 配置文件已存在，跳过"
fi


echo ""
echo ">>> 步骤 7/8: 创建并启动服务..."
cat > /etc/systemd/system/pi-network-backend.service <<EOF
[Unit]
Description=Pi Network Backend API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR/backend
Environment="NODE_ENV=production"
EnvironmentFile=$PROJECT_DIR/backend/.env
ExecStart=/usr/bin/node $PROJECT_DIR/backend/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pi-network-backend
systemctl restart pi-network-backend
echo "✓ 系统服务已创建并启动"

echo ""
echo ">>> 步骤 8/8: 验证部署..."
sleep 3

if systemctl is-active --quiet pi-network-backend; then
    echo "✓ 后端服务运行正常"
    
    response=$(curl -s -H "X-API-Key: $API_KEY" http://localhost:7008/api/status 2>/dev/null)
    if echo "$response" | grep -q "hysteria2\|xray"; then
        echo "✓ API 测试成功"
    else
        echo "⚠ API 响应异常，但服务已启动"
    fi
else
    echo "✗ 后端服务启动失败"
    echo "查看日志: journalctl -u pi-network-backend -n 50"
    exit 1
fi

echo ""
echo ">>> 配置防火墙..."
if command -v ufw &> /dev/null; then
    ufw allow 7008/tcp 2>/dev/null && echo "✓ UFW 防火墙已配置"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=7008/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    echo "✓ firewalld 防火墙已配置"
fi

echo ""
echo ">>> 清理临时文件..."
rm -rf $TEMP_DIR
echo "✓ 临时文件已清理"

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo "========================================="
echo "  部署完成！"
echo "========================================="
echo ""
echo "后端地址: http://${SERVER_IP}:7008"
echo "API Key: $API_KEY"
echo ""
echo "常用命令："
echo "  查看状态: systemctl status pi-network-backend"
echo "  查看日志: journalctl -u pi-network-backend -f"
echo "  重启服务: systemctl restart pi-network-backend"
echo ""
echo "客户端使用："
echo "  export API_KEY='$API_KEY'"
echo "  export BACKEND_URL='http://${SERVER_IP}:7008'"
echo "  bash Pi_Network.sh"
echo ""

echo -n "按回车键返回主菜单..."
read
show_menu
}

if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 权限运行"
    exit 1
fi

show_menu
