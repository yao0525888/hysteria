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
    echo "  2) API Key 管理"
    echo "  3) 修改 Hysteria2 密码"
    echo "  4) 修改 Xray UUID"
    echo "  5) 查看当前配置"
    echo "  6) 卸载后端服务"
    echo "  7) 退出"
    echo ""
    echo -n "请输入选项 [1-7]: "
    read -r choice
    
    case "$choice" in
        1) install_backend ;;
        2) manage_api_keys ;;
        3) change_hysteria_password ;;
        4) change_xray_uuid ;;
        5) show_config ;;
        6) uninstall_backend ;;
        7) echo "退出"; exit 0 ;;
        *) echo "无效选项"; sleep 2; show_menu ;;
    esac
}

manage_api_keys() {
    clear
    echo "========================================="
    echo "  API Key 管理 (多 API / 按次扣减)"
    echo "========================================="
    echo ""
    
    if [ ! -f "$PROJECT_DIR/backend/server.js" ]; then
        echo "✗ 后端服务未安装"
        echo "请先安装后端服务"
        echo ""
        echo -n "按回车键继续..."
        read
        show_menu
        return
    fi

    # 显示当前所有 Key 列表
    node "$PROJECT_DIR/backend/manage_keys.js" list 2>/dev/null || true

    echo "请选择操作："
    echo "  1) 添加新 API Key"
    echo "  2) 充值 API Key 次数"
    echo "  3) 重新设定 API Key 剩余次数"
    echo "  4) 启用/禁用 API Key"
    echo "  5) 删除 API Key"
    echo "  6) 查看指定 API Key 详情与客户端命令"
    echo "  7) 导出所有 API Key 到文件"
    echo "  0) 返回主菜单"
    echo ""
    echo -n "请输入选项 [0-7]: "
    read -r sub_choice

    case "$sub_choice" in
        1) add_api_key ;;
        2) recharge_api_key ;;
        3) set_api_key_count ;;
        4) toggle_api_key ;;
        5) delete_api_key ;;
        6) get_api_key_detail ;;
        7) export_api_keys ;;
        0) show_menu ;;
        *) echo "无效选项"; sleep 1; manage_api_keys ;;
    esac
}

add_api_key() {
    clear
    echo "========================================="
    echo "  添加新 API Key"
    echo "========================================="
    echo ""
    
    echo -n "请输入备注名称 (默认'新用户'): "
    read -r KEY_NAME
    if [ -z "$KEY_NAME" ]; then
        KEY_NAME="新用户"
    fi

    echo -n "请输入可用次数 (默认 100 次): "
    read -r KEY_COUNT
    if [ -z "$KEY_COUNT" ]; then
        KEY_COUNT=100
    fi

    if ! [[ "$KEY_COUNT" =~ ^[0-9]+$ ]]; then
        echo "✗ 错误：可用次数必须为非负整数"
        echo -n "按回车键继续..."
        read
        manage_api_keys
        return
    fi

    echo -n "请输入自定义 API Key: "
    read -r CUSTOM_KEY

    echo ""
    cd "$PROJECT_DIR/backend"
    if [ -n "$CUSTOM_KEY" ]; then
        node manage_keys.js add "$KEY_COUNT" "$KEY_NAME" "$CUSTOM_KEY"
    else
        node manage_keys.js add "$KEY_COUNT" "$KEY_NAME"
    fi

    echo ""
    echo -n "按回车键继续..."
    read
    manage_api_keys
}

recharge_api_key() {
    clear
    echo "========================================="
    echo "  充值 / 增加 API Key 次数"
    echo "========================================="
    echo ""
    node "$PROJECT_DIR/backend/manage_keys.js" list 2>/dev/null || true

    echo -n "请输入要充值的 API Key序号: "
    read -r TARGET_INPUT
    
    if [ -z "$TARGET_INPUT" ]; then
        echo "已取消"
        sleep 1
        manage_api_keys
        return
    fi

    TARGET_KEY="$TARGET_INPUT"
    # 如果用户输入的是纯数字序号，从 json 中查找对应 key
    if [[ "$TARGET_INPUT" =~ ^[0-9]+$ ]] && [ "$TARGET_INPUT" -gt 0 ]; then
        RESOLVED_KEY=$(node -e "
            const { apiKeyManager } = require('$PROJECT_DIR/backend/apiKeyManager');
            const list = apiKeyManager.getAllKeys();
            const idx = parseInt('$TARGET_INPUT', 10) - 1;
            if (list[idx]) console.log(list[idx].key);
        " 2>/dev/null || echo "")
        if [ -n "$RESOLVED_KEY" ]; then
            TARGET_KEY="$RESOLVED_KEY"
        fi
    fi

    echo -n "请输入要增加的次数 (例如: 50): "
    read -r ADD_COUNT

    if ! [[ "$ADD_COUNT" =~ ^[0-9]+$ ]] || [ "$ADD_COUNT" -le 0 ]; then
        echo "✗ 错误：增加的次数必须为大于 0 的整数"
        echo -n "按回车键继续..."
        read
        manage_api_keys
        return
    fi

    echo ""
    cd "$PROJECT_DIR/backend"
    node manage_keys.js recharge "$TARGET_KEY" "$ADD_COUNT"

    echo ""
    echo -n "按回车键继续..."
    read
    manage_api_keys
}

set_api_key_count() {
    clear
    echo "========================================="
    echo "  重新设定 API Key 剩余次数"
    echo "========================================="
    echo ""
    node "$PROJECT_DIR/backend/manage_keys.js" list 2>/dev/null || true

    echo -n "请输入要设定的 API Key 序号: "
    read -r TARGET_INPUT
    
    if [ -z "$TARGET_INPUT" ]; then
        echo "已取消"
        sleep 1
        manage_api_keys
        return
    fi

    TARGET_KEY="$TARGET_INPUT"
    if [[ "$TARGET_INPUT" =~ ^[0-9]+$ ]] && [ "$TARGET_INPUT" -gt 0 ]; then
        RESOLVED_KEY=$(node -e "
            const { apiKeyManager } = require('$PROJECT_DIR/backend/apiKeyManager');
            const list = apiKeyManager.getAllKeys();
            const idx = parseInt('$TARGET_INPUT', 10) - 1;
            if (list[idx]) console.log(list[idx].key);
        " 2>/dev/null || echo "")
        if [ -n "$RESOLVED_KEY" ]; then
            TARGET_KEY="$RESOLVED_KEY"
        fi
    fi

    echo -n "请输入新的剩余可用次数: "
    read -r NEW_COUNT

    if ! [[ "$NEW_COUNT" =~ ^[0-9]+$ ]]; then
        echo "✗ 错误：次数必须为非负整数"
        echo -n "按回车键继续..."
        read
        manage_api_keys
        return
    fi

    echo ""
    cd "$PROJECT_DIR/backend"
    node manage_keys.js set-count "$TARGET_KEY" "$NEW_COUNT"

    echo ""
    echo -n "按回车键继续..."
    read
    manage_api_keys
}

toggle_api_key() {
    clear
    echo "========================================="
    echo "  启用 / 禁用 API Key"
    echo "========================================="
    echo ""
    node "$PROJECT_DIR/backend/manage_keys.js" list 2>/dev/null || true

    echo -n "请输入要切换状态的 API Key序号: "
    read -r TARGET_INPUT
    
    if [ -z "$TARGET_INPUT" ]; then
        echo "已取消"
        sleep 1
        manage_api_keys
        return
    fi

    TARGET_KEY="$TARGET_INPUT"
    if [[ "$TARGET_INPUT" =~ ^[0-9]+$ ]] && [ "$TARGET_INPUT" -gt 0 ]; then
        RESOLVED_KEY=$(node -e "
            const { apiKeyManager } = require('$PROJECT_DIR/backend/apiKeyManager');
            const list = apiKeyManager.getAllKeys();
            const idx = parseInt('$TARGET_INPUT', 10) - 1;
            if (list[idx]) console.log(list[idx].key);
        " 2>/dev/null || echo "")
        if [ -n "$RESOLVED_KEY" ]; then
            TARGET_KEY="$RESOLVED_KEY"
        fi
    fi

    echo ""
    cd "$PROJECT_DIR/backend"
    node manage_keys.js toggle "$TARGET_KEY"

    echo ""
    echo -n "按回车键继续..."
    read
    manage_api_keys
}

delete_api_key() {
    clear
    echo "========================================="
    echo "  删除 API Key"
    echo "========================================="
    echo ""
    node "$PROJECT_DIR/backend/manage_keys.js" list 2>/dev/null || true

    echo -n "请输入要删除的 API Key序号: "
    read -r TARGET_INPUT
    
    if [ -z "$TARGET_INPUT" ]; then
        echo "已取消"
        sleep 1
        manage_api_keys
        return
    fi

    TARGET_KEY="$TARGET_INPUT"
    if [[ "$TARGET_INPUT" =~ ^[0-9]+$ ]] && [ "$TARGET_INPUT" -gt 0 ]; then
        RESOLVED_KEY=$(node -e "
            const { apiKeyManager } = require('$PROJECT_DIR/backend/apiKeyManager');
            const list = apiKeyManager.getAllKeys();
            const idx = parseInt('$TARGET_INPUT', 10) - 1;
            if (list[idx]) console.log(list[idx].key);
        " 2>/dev/null || echo "")
        if [ -n "$RESOLVED_KEY" ]; then
            TARGET_KEY="$RESOLVED_KEY"
        fi
    fi

    echo ""
    echo -n "警告：确定要删除该 API Key 吗？此操作不可恢复 (y/n): "
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        cd "$PROJECT_DIR/backend"
        node manage_keys.js delete "$TARGET_KEY"
    else
        echo "已取消"
    fi

    echo ""
    echo -n "按回车键继续..."
    read
    manage_api_keys
}

get_api_key_detail() {
    clear
    echo "========================================="
    echo "  查看 API Key 详情与调用命令"
    echo "========================================="
    echo ""
    node "$PROJECT_DIR/backend/manage_keys.js" list 2>/dev/null || true

    echo -n "请输入要查看的 API Key序号: "
    read -r TARGET_INPUT
    
    if [ -z "$TARGET_INPUT" ]; then
        echo "已取消"
        sleep 1
        manage_api_keys
        return
    fi

    TARGET_KEY="$TARGET_INPUT"
    if [[ "$TARGET_INPUT" =~ ^[0-9]+$ ]] && [ "$TARGET_INPUT" -gt 0 ]; then
        RESOLVED_KEY=$(node -e "
            const { apiKeyManager } = require('$PROJECT_DIR/backend/apiKeyManager');
            const list = apiKeyManager.getAllKeys();
            const idx = parseInt('$TARGET_INPUT', 10) - 1;
            if (list[idx]) console.log(list[idx].key);
        " 2>/dev/null || echo "")
        if [ -n "$RESOLVED_KEY" ]; then
            TARGET_KEY="$RESOLVED_KEY"
        fi
    fi

    cd "$PROJECT_DIR/backend"
    node manage_keys.js get "$TARGET_KEY"

    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    PORT=$(grep "^PORT=" "$PROJECT_DIR/backend/.env" 2>/dev/null | cut -d'=' -f2 || echo "7008")
    
    echo "----------------------------------------"
    echo "客户端调用方式 (任选其一)："
    echo "1. 命令行环境变量方式："
    echo "   export API_KEY=\"$TARGET_KEY\""
    echo "   bash xray2.sh"
    echo ""
    echo "2. 直接写入客户端脚本头部："
    echo "   API_KEY=\"$TARGET_KEY\""
    echo "----------------------------------------"

    echo ""
    echo -n "按回车键继续..."
    read
    manage_api_keys
}

export_api_keys() {
    clear
    echo "========================================="
    echo "  导出所有 API Key 到文件"
    echo "========================================="
    echo ""
    EXPORT_FILE="/root/pi-network-all-keys.txt"
    cd "$PROJECT_DIR/backend"
    node manage_keys.js export "$EXPORT_FILE"

    echo ""
    echo "文件内容预览："
    cat "$EXPORT_FILE"
    echo ""
    echo -n "按回车键继续..."
    read
    manage_api_keys
}

change_hysteria_password() {
    clear
    echo "========================================="
    echo "  修改 Hysteria2 密码"
    echo "========================================="
    echo ""
    
    if [ ! -f "$PROJECT_DIR/backend/.env" ]; then
        echo "✗ 后端服务未安装"
        echo "请先安装后端服务"
        sleep 3
        show_menu
        return
    fi
    
    echo "当前 Hysteria2 密码:"
    OLD_PASSWORD=$(grep "^HYSTERIA_PASSWORD=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    echo "$OLD_PASSWORD"
    echo ""
    echo -n "请输入新的 Hysteria2 密码 (直接回车生成随机 UUID): "
    read -r NEW_PASSWORD
    
    if [ -z "$NEW_PASSWORD" ]; then
        if command -v uuidgen &> /dev/null; then
            NEW_PASSWORD=$(uuidgen)
        elif [ -f /proc/sys/kernel/random/uuid ]; then
            NEW_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
        else
            hex=$(openssl rand -hex 16)
            NEW_PASSWORD="${hex:0:8}-${hex:8:4}-${hex:12:4}-${hex:16:4}-${hex:20:12}"
        fi
        echo "已生成随机 UUID 格式密码: $NEW_PASSWORD"
    fi
    
    echo ""
    echo -n "确认修改 Hysteria2 密码？(y/n): "
    read -r confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        sed -i "s/^HYSTERIA_PASSWORD=.*/HYSTERIA_PASSWORD=$NEW_PASSWORD/" $PROJECT_DIR/backend/.env
        echo "$NEW_PASSWORD" > /root/pi-network-hysteria-password.txt
        
        systemctl restart pi-network-backend
        
        echo ""
        echo "✓ Hysteria2 密码已更新"
        echo "✓ 后端服务已重启"
        echo "✓ 密码 已保存到: /root/pi-network-hysteria-password.txt"
        echo ""
        echo "新的 Hysteria2 密码: $NEW_PASSWORD"
        echo ""
        echo "注意: 修改密码后，需要重新部署客户端配置才能生效"
        echo "客户端需要重新运行安装脚本或更新配置文件"
    else
        echo "已取消"
    fi
    
    echo ""
    echo -n "按回车键继续..."
    read
    show_menu
}

change_xray_uuid() {
    clear
    echo "========================================="
    echo "  修改 Xray UUID"
    echo "========================================="
    echo ""
    
    if [ ! -f "$PROJECT_DIR/backend/.env" ]; then
        echo "✗ 后端服务未安装"
        echo "请先安装后端服务"
        sleep 3
        show_menu
        return
    fi
    
    echo "当前 Xray UUID:"
    OLD_UUID=$(grep "^XRAY_UUID=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    echo "$OLD_UUID"
    echo ""
    echo -n "请输入新的 Xray UUID (直接回车生成随机 UUID): "
    read -r NEW_UUID
    
    if [ -z "$NEW_UUID" ]; then
        if command -v uuidgen &> /dev/null; then
            NEW_UUID=$(uuidgen)
        elif [ -f /proc/sys/kernel/random/uuid ]; then
            NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
        else
            hex=$(openssl rand -hex 16)
            NEW_UUID="${hex:0:8}-${hex:8:4}-${hex:12:4}-${hex:16:4}-${hex:20:12}"
        fi
        echo "已生成随机 UUID: $NEW_UUID"
    fi
    
    echo ""
    echo -n "确认修改 Xray UUID？(y/n): "
    read -r confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        sed -i "s/^XRAY_UUID=.*/XRAY_UUID=$NEW_UUID/" $PROJECT_DIR/backend/.env
        echo "$NEW_UUID" > /root/pi-network-xray-uuid.txt
        
        systemctl restart pi-network-backend
        
        echo ""
        echo "✓ Xray UUID 已更新"
        echo "✓ 后端服务已重启"
        echo "✓ UUID 已保存到: /root/pi-network-xray-uuid.txt"
        echo ""
        echo "新的 Xray UUID: $NEW_UUID"
        echo ""
        echo "注意: 修改 UUID 后，需要重新部署客户端配置才能生效"
        echo "客户端需要重新运行安装脚本或更新配置文件"
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
        systemctl stop pi-network-backend 2>/dev/null || true
        systemctl disable pi-network-backend 2>/dev/null || true
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
            firewall-cmd --permanent --remove-port=7008/tcp 2>/dev/null || true
            firewall-cmd --reload 2>/dev/null || true
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
    
    PORT=$(grep "^PORT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    ENABLE_LIMIT=$(grep "^ENABLE_LIMIT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    
    HYSTERIA_PORT=$(grep "^HYSTERIA_PORT=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    HYSTERIA_PASSWORD=$(grep "^HYSTERIA_PASSWORD=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    HYSTERIA_MASQUERADE_HOST=$(grep "^HYSTERIA_MASQUERADE_HOST=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    
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
    echo "基础配置:"
    echo "  后端地址: http://${SERVER_IP}:${PORT}"
    echo "  项目目录: $PROJECT_DIR"
    echo "  限速开关: $ENABLE_LIMIT"
    echo ""
    echo "API Key 概况 (多 API 支持):"
    if [ -f "$PROJECT_DIR/backend/manage_keys.js" ]; then
        node "$PROJECT_DIR/backend/manage_keys.js" list 2>/dev/null || true
    fi
    echo "  提示: 可在主菜单选择 [2) API Key 管理] 新增或修改 Key 次数"
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
        systemctl stop pi-network-backend 2>/dev/null || true
        systemctl disable pi-network-backend 2>/dev/null || true
        rm -f /etc/systemd/system/pi-network-backend.service
        systemctl daemon-reload
        echo "✓ 旧服务已卸载"
    fi

    if [ -d "$PROJECT_DIR" ]; then
        echo "发现已存在的项目目录，正在清理..."
        rm -rf $PROJECT_DIR
        echo "✓ 旧项目文件已清理"
    fi

    DOWNLOAD_URL="https://github.com/yao0525888/hysteria/releases/download/v1/xray-backend.tar.gz"
    TEMP_DIR="/tmp/pi-network-install"
    PROJECT_DIR="/opt/pi-network"

    echo ">>> 步骤 1/8: 安装必要工具..."
    apt-get update -qq
    apt-get install -y wget curl tar swaks

    echo ""
    echo ">>> 步骤 2/8: 获取项目文件..."
    mkdir -p $TEMP_DIR
    cd $TEMP_DIR

    if [ -d "/root/pi-network-backend" ]; then
        echo "发现本地项目文件 /root/pi-network-backend，正在复制..."
        cp -r /root/pi-network-backend pi-network
        if [ $? -eq 0 ]; then
            echo "✓ 本地文件复制完成"
        else
            echo "✗ 本地文件复制失败"
            exit 1
        fi
    elif [ -f "/root/xray-backend.tar.gz" ]; then
        echo "发现本地安装包 /root/xray-backend.tar.gz，正在解压..."
        mkdir -p pi-network
        tar -xzf /root/xray-backend.tar.gz -C pi-network
        echo "✓ 本地安装包解压完成"
    else
        echo "未发现本地项目文件，正在从 GitHub 下载... (如果失败会自动重试)"
        for i in {1..3}; do
            if wget -T 30 -t 3 --show-progress $DOWNLOAD_URL -O xray-backend.tar.gz; then
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
                    echo "2. 上传到服务器 /tmp/xray-backend.tar.gz"
                    echo "3. 或者将解压后的项目文件放到 /root/pi-network-backend"
                    echo "4. 重新运行此脚本"
                    exit 1
                fi
            fi
        done

        echo ""
        echo ">>> 步骤 3/8: 解压文件..."
        mkdir -p pi-network
        tar -xzf xray-backend.tar.gz -C pi-network
        if [ $? -ne 0 ]; then
            echo "✗ 解压失败"
            exit 1
        fi
        echo "✓ 解压完成"
    fi

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
    elif [ -d "$TEMP_DIR/pi-network" ]; then
        cp -r $TEMP_DIR/pi-network $PROJECT_DIR/backend
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
        DEFAULT_API_KEY=$(grep "^API_KEY=" env.example 2>/dev/null | cut -d'=' -f2 || echo "")
        if [ -z "$DEFAULT_API_KEY" ]; then
            API_KEY=$(openssl rand -hex 32)
        else
            API_KEY="$DEFAULT_API_KEY"
        fi
        
        cp env.example .env
        sed -i "s/^API_KEY=.*/API_KEY=$API_KEY/" .env
        
        echo "✓ 配置文件已生成"
    else
        API_KEY=$(grep "^API_KEY=" .env | cut -d'=' -f2)
        echo "✓ 配置文件已存在，跳过"
    fi

    # 初始化 API Key 存储
    echo ">>> 初始化 API Key 数据存储..."
    node -e "require('./apiKeyManager');" 2>/dev/null || true
    echo "API_KEY=$API_KEY" > /root/pi-network-api-key.txt
    node manage_keys.js export /root/pi-network-all-keys.txt 2>/dev/null || true

    echo ""
    echo "========================================="
    echo "  重要！默认 API Key 已生成："
    echo "  Key:      $API_KEY"
    echo "  初始可用: 1000 次 (按次扣减)"
    echo "  管理方式: 执行脚本选择菜单 2) 可管理多 API Key"
    echo "========================================="
    echo ""

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
        
        response=$(curl -s -H "X-API-Key: $API_KEY" http://localhost:7008/api/status 2>/dev/null || echo "")
        if echo "$response" | grep -q "hysteria2\|xray\|remaining_count"; then
            echo "✓ API 鉴权与状态测试成功"
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
        firewall-cmd --permanent --add-port=7008/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
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
    echo "默认 API Key: $API_KEY"
    echo ""
    echo "常用命令："
    echo "  查看状态: systemctl status pi-network-backend"
    echo "  查看日志: journalctl -u pi-network-backend -f"
    echo "  重启服务: systemctl restart pi-network-backend"
    echo ""
    echo "客户端使用："
    echo "  export API_KEY=\"$API_KEY\""
    echo ""
    echo -n "按回车键继续..."
    read
    show_menu
}

show_menu
