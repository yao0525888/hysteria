#!/bin/bash

echo "=========================================="
echo "  客户数据管理系统 - Linux部署脚本"
echo "=========================================="
echo ""

WEB_DIR="/var/www/html"
# 主文件（默认端口提供）
FILE_NAME="default.html"
GITHUB_URL="https://github.com/yao0525888/hysteria/releases/download/v1/default.html"
# 备用文件（额外端口提供 default1.html）
SECONDARY_FILE="default1.html"
SECONDARY_URL="https://github.com/yao0525888/hysteria/releases/download/v1/default1.html"
PORT="7009"
SECONDARY_PORT="7011"
HTTPS_PORT="$PORT"
API_PORT="7010"
CURRENT_DIR=$(pwd)

if [ "$EUID" -ne 0 ]; then 
    echo "错误：请使用sudo运行此脚本"
    exit 1
fi

echo "请选择操作："
echo "1) 安装1"
echo "2) 卸载"
echo "3) 更新 default.html 文件"
echo "4) 更新 default1.html 文件"
echo "5) 申请/更新HTTPS证书"
read -p "请输入选项 [1-5] (默认1): " action
action=${action:-1}

if [ "$action" = "3" ]; then
    echo ""
    echo "=========================================="
    echo "  更新 default.html 文件"
    echo "=========================================="
    echo ""
    
    if [ ! -f "$WEB_DIR/$FILE_NAME" ]; then
        echo "错误：未找到已部署的 $FILE_NAME 文件"
        echo "请先运行安装选项（选项1）"
        exit 1
    fi
    
    echo "正在备份当前文件..."
    BACKUP_FILE_MAIN="$WEB_DIR/${FILE_NAME}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$WEB_DIR/$FILE_NAME" "$BACKUP_FILE_MAIN" 2>/dev/null || true
    if [ -f "$BACKUP_FILE_MAIN" ]; then
        echo "备份已创建: $BACKUP_FILE_MAIN"
    else
        echo "警告：无法创建备份文件，继续更新..."
    fi
    
    download_or_copy() {
        local src_file=$1
        local url=$2
        local target=$3
        local label=$4
        if [ -f "$src_file" ]; then
            echo "检测到本地 $label 文件，使用本地文件..."
            cp "$src_file" "$target"
            return
        fi
        echo "正在从GitHub下载 $label ..."
        if command -v wget &> /dev/null; then
            wget -q "$url" -O "${target}.new" 2>/dev/null
        elif command -v curl &> /dev/null; then
            curl -sL "$url" -o "${target}.new" 2>/dev/null
        else
            echo "错误：未找到wget或curl，无法下载 $label"
            exit 1
        fi
        if [ -f "${target}.new" ] && [ -s "${target}.new" ]; then
            mv "${target}.new" "$target"
        else
            echo "错误：$label 下载无效"
            rm -f "${target}.new" 2>/dev/null || true
            exit 1
        fi
    }

    download_or_copy "$CURRENT_DIR/$FILE_NAME" "$GITHUB_URL" "$WEB_DIR/$FILE_NAME" "$FILE_NAME"
    
    echo "设置文件权限..."
    chown www-data:www-data "$WEB_DIR/$FILE_NAME" 2>/dev/null || chown nginx:nginx "$WEB_DIR/$FILE_NAME" 2>/dev/null || chown root:root "$WEB_DIR/$FILE_NAME" 2>/dev/null || true
    chmod 644 "$WEB_DIR/$FILE_NAME"
    
    echo "重新加载Nginx配置..."
    if pgrep -x nginx > /dev/null; then
        if systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true; then
            echo "Nginx配置已重新加载"
        else
            NGINX_BIN=""
            if command -v nginx &> /dev/null; then
                NGINX_BIN=$(which nginx)
            elif [ -f "/usr/local/nginx/sbin/nginx" ]; then
                NGINX_BIN="/usr/local/nginx/sbin/nginx"
            fi
            if [ -n "$NGINX_BIN" ]; then
                $NGINX_BIN -s reload 2>/dev/null || echo "警告：无法重新加载Nginx，但文件已更新"
            fi
        fi
    else
        echo "警告：Nginx未运行，文件已更新但需要手动启动Nginx"
    fi
    
    echo ""
    echo "=========================================="
    echo "✅ 文件更新完成！"
    echo "=========================================="
    echo ""
    if [ -f "$BACKUP_FILE_MAIN" ]; then
        echo "备份文件位置: $BACKUP_FILE_MAIN"
        echo "如需恢复，请运行: cp $BACKUP_FILE_MAIN $WEB_DIR/$FILE_NAME"
    fi
    echo ""
    exit 0
fi

# 独立更新 default1.html
if [ "$action" = "4" ]; then
    echo ""
    echo "=========================================="
    echo "  更新 default1.html 文件"
    echo "=========================================="
    echo ""
    
    if [ ! -f "$WEB_DIR/$SECONDARY_FILE" ]; then
        echo "错误：未找到已部署的 $SECONDARY_FILE 文件"
        echo "请先运行安装选项（选项1）"
        exit 1
    fi
    
    echo "正在备份当前文件..."
    BACKUP_FILE_SEC="$WEB_DIR/${SECONDARY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$WEB_DIR/$SECONDARY_FILE" "$BACKUP_FILE_SEC" 2>/dev/null || true
    if [ -f "$BACKUP_FILE_SEC" ]; then
        echo "备份已创建: $BACKUP_FILE_SEC"
    else
        echo "警告：无法创建备份文件，继续更新..."
    fi
    
    download_or_copy() {
        local src_file=$1
        local url=$2
        local target=$3
        local label=$4
        if [ -f "$src_file" ]; then
            echo "检测到本地 $label 文件，使用本地文件..."
            cp "$src_file" "$target"
            return
        fi
        echo "正在从GitHub下载 $label ..."
        if command -v wget &> /dev/null; then
            wget -q "$url" -O "${target}.new" 2>/dev/null
        elif command -v curl &> /dev/null; then
            curl -sL "$url" -o "${target}.new" 2>/dev/null
        else
            echo "错误：未找到wget或curl，无法下载 $label"
            exit 1
        fi
        if [ -f "${target}.new" ] && [ -s "${target}.new" ]; then
            mv "${target}.new" "$target"
        else
            echo "错误：$label 下载无效"
            rm -f "${target}.new" 2>/dev/null || true
            exit 1
        fi
    }

    download_or_copy "$CURRENT_DIR/$SECONDARY_FILE" "$SECONDARY_URL" "$WEB_DIR/$SECONDARY_FILE" "$SECONDARY_FILE"
    
    echo "设置文件权限..."
    chown www-data:www-data "$WEB_DIR/$SECONDARY_FILE" 2>/dev/null || chown nginx:nginx "$WEB_DIR/$SECONDARY_FILE" 2>/dev/null || chown root:root "$WEB_DIR/$SECONDARY_FILE" 2>/dev/null || true
    chmod 644 "$WEB_DIR/$SECONDARY_FILE"
    
    echo "重新加载Nginx配置..."
    if pgrep -x nginx > /dev/null; then
        if systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true; then
            echo "Nginx配置已重新加载"
        else
            NGINX_BIN=""
            if command -v nginx &> /dev/null; then
                NGINX_BIN=$(which nginx)
            elif [ -f "/usr/local/nginx/sbin/nginx" ]; then
                NGINX_BIN="/usr/local/nginx/sbin/nginx"
            fi
            if [ -n "$NGINX_BIN" ]; then
                $NGINX_BIN -s reload 2>/dev/null || echo "警告：无法重新加载Nginx，但文件已更新"
            fi
        fi
    else
        echo "警告：Nginx未运行，文件已更新但需要手动启动Nginx"
    fi
    
    echo ""
    echo "=========================================="
    echo "✅ 文件更新完成！"
    echo "=========================================="
    echo ""
    if [ -f "$BACKUP_FILE_SEC" ]; then
        echo "备份文件位置: $BACKUP_FILE_SEC"
        echo "如需恢复，请运行: cp $BACKUP_FILE_SEC $WEB_DIR/$SECONDARY_FILE"
    fi
    echo ""
    exit 0
fi

if [ "$action" = "5" ]; then
    echo ""
    echo "=========================================="
    echo "  申请/更新HTTPS证书"
    echo "=========================================="
    echo ""
    
    if ! command -v nginx &> /dev/null && [ ! -f "/usr/local/nginx/sbin/nginx" ]; then
        echo "错误：未检测到已安装的Nginx，请先执行安装步骤（选项1）"
        exit 1
    fi
    
    ensure_ssl_module() {
        if [ -n "$NGINX_BIN" ] && $NGINX_BIN -V 2>&1 | grep -q "http_ssl_module"; then
            return 0
        fi
        echo "检测到当前Nginx未启用SSL模块，尝试自动编译启用SSL..."
        BUILD_DIR="/tmp/nginx-build-ssl"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        MISSING_DEPS=""
        command -v gcc >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS gcc"
        command -v make >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS make"
        command -v git >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS git"
        OPENSSL_CHECK=false
        if [ -f /usr/include/openssl/ssl.h ] || [ -f /usr/local/include/openssl/ssl.h ]; then
            OPENSSL_CHECK=true
        fi
        if [ "$OPENSSL_CHECK" = false ]; then
            if command -v apt-get &> /dev/null; then
                MISSING_DEPS="$MISSING_DEPS libssl-dev"
            elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                MISSING_DEPS="$MISSING_DEPS openssl-devel"
            fi
        fi
        if [ -n "$MISSING_DEPS" ]; then
            echo "安装SSL编译依赖: $MISSING_DEPS"
            if command -v apt-get &> /dev/null; then
                apt-get update -y 2>/dev/null || true
                apt-get install -y $MISSING_DEPS 2>/dev/null || true
            elif command -v yum &> /dev/null; then
                yum install -y $MISSING_DEPS 2>/dev/null || true
            elif command -v dnf &> /dev_null; then
                dnf install -y $MISSING_DEPS 2>/dev/null || true
            fi
        fi

        if git clone https://github.com/nginx/nginx.git 2>/dev/null; then
            cd nginx
            if auto/configure --prefix=/usr/local/nginx --with-http_ssl_module >/dev/null 2>&1; then
                if make -j$(nproc 2>/dev/null || echo 1) >/dev/null 2>&1 && make install >/dev/null 2>&1; then
                    if [ -f "/usr/local/nginx/sbin/nginx" ]; then
                        ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx 2>/dev/null || true
                        ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx 2>/dev/null || true
                        cd /
                        rm -rf "$BUILD_DIR"
                        NGINX_BIN="/usr/local/nginx/sbin/nginx"
                        echo "Nginx已重新编译并启用SSL模块"
                        return 0
                    fi
                fi
            fi
        fi
        echo "自动编译启用SSL失败，请手动确保安装带http_ssl_module的Nginx"
        return 1
    }

    if ! ensure_ssl_module; then
        echo "错误：Nginx未启用SSL模块，无法配置HTTPS"
        exit 1
    fi

    setup_nginx_service() {
        if [ -f "/etc/systemd/system/nginx.service" ]; then
            return 0
        fi
        if [ -x "/usr/local/nginx/sbin/nginx" ]; then
            cat > /etc/systemd/system/nginx.service <<'EOF'
[Unit]
Description=The nginx HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/usr/local/nginx/logs/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t -c /usr/local/nginx/conf/nginx.conf
ExecStart=/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s quit
TimeoutStopSec=5
KillMode=process
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload 2>/dev/null || true
            systemctl enable nginx 2>/dev/null || true
        fi
    }

    manage_nginx_with_systemd() {
        # 如果已有 systemd 管控实例，优先重载
        if systemctl is-active --quiet nginx 2>/dev/null; then
            systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
            return 0
        fi
        # 如果有手工启动的 nginx 占用端口，先停掉
        if pgrep -x nginx > 0 2>/dev/null; then
            pkill -9 nginx 2>/dev/null || true
        fi
        rm -f /usr/local/nginx/logs/nginx.pid /var/run/nginx.pid
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable nginx 2>/dev/null || true
        systemctl start nginx 2>/dev/null || service nginx start 2>/dev/null || true
    }
    
    if [ ! -d "$WEB_DIR" ] || [ ! -f "$WEB_DIR/$FILE_NAME" ]; then
        echo "错误：未找到已部署的网页文件，请先完成安装（选项1）"
        exit 1
    fi
    
    NGINX_CONF_DIR=""
    NGINX_CONF_FILE=""
    if [ -d "/usr/local/nginx/conf" ]; then
        NGINX_CONF_DIR="/usr/local/nginx/conf"
        NGINX_CONF_FILE="/usr/local/nginx/conf/nginx.conf"
    elif [ -d "/etc/nginx" ]; then
        NGINX_CONF_DIR="/etc/nginx"
        NGINX_CONF_FILE="/etc/nginx/nginx.conf"
    else
        echo "错误：未找到Nginx配置目录，请检查Nginx安装"
        exit 1
    fi
    
    NGINX_BIN=""
    if command -v nginx &> /dev/null; then
        NGINX_BIN=$(which nginx)
    elif [ -f "/usr/local/nginx/sbin/nginx" ]; then
        NGINX_BIN="/usr/local/nginx/sbin/nginx"
    fi
    
    read -p "请输入域名（可空格分隔多个，例如 example.com www.example.com）: " DOMAIN_INPUT
    DOMAIN_INPUT=$(echo "$DOMAIN_INPUT" | xargs)
    if [ -z "$DOMAIN_INPUT" ]; then
        echo "错误：域名不能为空"
        exit 1
    fi
    
    PRIMARY_DOMAIN=$(echo "$DOMAIN_INPUT" | awk '{print $1}')
    read -p "请输入证书通知邮箱(可选，回车跳过): " CERT_EMAIL
    CERT_EMAIL=$(echo "$CERT_EMAIL" | xargs)
    REDIRECT_SUFFIX=""
    if [ "$HTTPS_PORT" != "443" ]; then
        REDIRECT_SUFFIX=":$HTTPS_PORT"
    fi
    
    echo ""
    echo "创建ACME验证配置（80端口）..."
    mkdir -p "$NGINX_CONF_DIR/conf.d"
    mkdir -p "$WEB_DIR/.well-known/acme-challenge"
    rm -f "$NGINX_CONF_DIR/conf.d/customer-data-acme.conf" "$NGINX_CONF_DIR/conf.d/00-customer-data-acme.conf" 2>/dev/null || true
    ACME_CONF="$NGINX_CONF_DIR/conf.d/00-customer-data-acme.conf"
    cat > "$ACME_CONF" <<EOF
 server {
    listen 80;
    server_name $DOMAIN_INPUT;
    root $WEB_DIR;
    location /.well-known/acme-challenge/ {
        alias $WEB_DIR/.well-known/acme-challenge/;
        try_files \$uri =404;
    }
    location / {
        return 301 https://$PRIMARY_DOMAIN$REDIRECT_SUFFIX$request_uri;
    }
}
EOF
    
    echo "重新加载Nginx以确保80端口可用于证书验证..."
    setup_nginx_service
    manage_nginx_with_systemd
    
    install_certbot() {
        if command -v certbot &> /dev/null; then
            return 0
        fi
        
        echo "正在安装certbot（申请Let's Encrypt证书）..."
        if command -v apt-get &> /dev/null; then
            apt-get update -y 2>/dev/null || true
            apt-get install -y certbot 2>/dev/null || {
                echo "apt安装certbot失败，请手动安装: sudo apt-get install -y certbot"
                return 1
            }
        elif command -v yum &> /dev/null; then
            yum install -y certbot 2>/dev/null || {
                echo "yum安装certbot失败，请手动安装: sudo yum install -y certbot"
                return 1
            }
        elif command -v dnf &> /dev/null; then
            dnf install -y certbot 2>/dev/null || {
                echo "dnf安装certbot失败，请手动安装: sudo dnf install -y certbot"
                return 1
            }
        else
            echo "未找到可用的包管理器，请手动安装certbot"
            return 1
        fi
    }
    
    if ! install_certbot; then
        echo "错误：certbot未安装，无法申请证书"
        exit 1
    fi
    
    CERTBOT_CMD="certbot certonly --webroot -w $WEB_DIR"
    for d in $DOMAIN_INPUT; do
        CERTBOT_CMD="$CERTBOT_CMD -d $d"
    done
    
    if [ -n "$CERT_EMAIL" ]; then
        CERTBOT_CMD="$CERTBOT_CMD -m $CERT_EMAIL --agree-tos"
    else
        CERTBOT_CMD="$CERTBOT_CMD --register-unsafely-without-email --agree-tos"
    fi
    
    CERTBOT_CMD="$CERTBOT_CMD --non-interactive --expand"
    
    echo ""
    echo "开始申请/更新证书..."
    if eval "$CERTBOT_CMD"; then
        echo "证书申请成功"
    else
        echo "错误：证书申请失败，请检查域名解析和80端口是否可访问"
        exit 1
    fi
    
    SSL_CERT="/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem"
    
    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
        echo "错误：未找到生成的证书文件"
        exit 1
    fi
    
    echo "创建HTTPS站点配置（443端口）..."
    rm -f "$NGINX_CONF_DIR/conf.d/customer-data-ssl.conf" "$NGINX_CONF_DIR/conf.d/01-customer-data-ssl.conf" "$NGINX_CONF_DIR/conf.d/customer-data.conf" "$NGINX_CONF_DIR/conf.d/customer-data.conf.http.bak" 2>/dev/null || true
    SSL_CONF="$NGINX_CONF_DIR/conf.d/01-customer-data-ssl.conf"
    cat > "$SSL_CONF" <<EOF
server {
    listen 80 default_server;
    server_name _;
    root $WEB_DIR;
    location /.well-known/acme-challenge/ {
        alias $WEB_DIR/.well-known/acme-challenge/;
        try_files \$uri =404;
    }
    location / {
        return 301 https://\$host$request_uri;
    }
}

 server {
    listen $HTTPS_PORT ssl default_server;
    server_name $DOMAIN_INPUT;
    root $WEB_DIR;
    index $FILE_NAME;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }

    location = / {
        try_files /$FILE_NAME =404;
    }
    
    location / {
        try_files \$uri \$uri/ /$FILE_NAME;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}

# 备用端口 7011 提供 HTTPS 访问 default1.html
server {
    listen $SECONDARY_PORT ssl;
    server_name $DOMAIN_INPUT;
    root $WEB_DIR;
    index $SECONDARY_FILE;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }

    location = / {
        try_files /$SECONDARY_FILE =404;
    }
    
    location / {
        try_files \$uri \$uri/ /$SECONDARY_FILE;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
    
    if [ "$HTTPS_PORT" = "$PORT" ]; then
        if [ -f "$NGINX_CONF_DIR/conf.d/customer-data.conf" ]; then
            mv "$NGINX_CONF_DIR/conf.d/customer-data.conf" "$NGINX_CONF_DIR/conf.d/customer-data.conf.http.bak" 2>/dev/null || true
        fi
        if [ -f "/etc/nginx/sites-enabled/customer-data" ]; then
            rm -f /etc/nginx/sites-enabled/customer-data 2>/dev/null || true
        fi
        if [ -f "/etc/nginx/sites-available/customer-data" ]; then
            mv /etc/nginx/sites-available/customer-data /etc/nginx/sites-available/customer-data.http.bak 2>/dev/null || true
        fi
    fi
    
    echo "重新加载Nginx以启用HTTPS..."
    setup_nginx_service
    manage_nginx_with_systemd
    
    echo "开放80/443及备用端口（如有防火墙）..."
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp 2>/dev/null || true
        ufw allow $HTTPS_PORT/tcp 2>/dev/null || true
        ufw allow $SECONDARY_PORT/tcp 2>/dev/null || true
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=$HTTPS_PORT/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=$SECONDARY_PORT/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi
    
    echo ""
    echo "=========================================="
    echo "✅ 证书申请与HTTPS配置完成"
    echo "=========================================="
    echo "证书路径: $SSL_CERT"
    echo "密钥路径: $SSL_KEY"
    echo "访问地址: https://$PRIMARY_DOMAIN$REDIRECT_SUFFIX"
    echo ""
    echo "若更新证书，重复选择该选项即可。certbot会自动续期（见 /etc/letsencrypt/renewal）。"
    echo "如需同时保留原有 $PORT 端口访问，可保留原配置；若不需要，可移除对应conf。"
    exit 0
fi

if [ "$action" = "2" ]; then
    echo ""
    echo "=========================================="
    echo "  卸载Nginx和部署文件"
    echo "=========================================="
    echo ""
    
    echo "正在停止API服务器..."
    systemctl stop customer-data-api.service 2>/dev/null || true
    pkill -f "api_server.py" 2>/dev/null || true
    
    echo "正在禁用API服务器服务..."
    systemctl disable customer-data-api.service 2>/dev/null || true
    
    echo "正在停止Nginx服务..."
    systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null || /etc/init.d/nginx stop 2>/dev/null || true
    
    echo "正在禁用Nginx服务..."
    systemctl disable nginx 2>/dev/null || true
    
    echo "正在删除systemd服务文件..."
    rm -f /etc/systemd/system/nginx.service
    rm -f /etc/systemd/system/customer-data-api.service
    systemctl daemon-reload 2>/dev/null || true
    
    echo "正在删除Nginx配置文件..."
    if [ -d "/etc/nginx" ]; then
        rm -rf /etc/nginx/sites-available/customer-data 2>/dev/null || true
        rm -f /etc/nginx/sites-enabled/customer-data 2>/dev/null || true
        rm -f /etc/nginx/conf.d/customer-data.conf 2>/dev/null || true
    fi
    
    echo "正在删除部署的网页文件..."
    if [ -f "$WEB_DIR/$FILE_NAME" ]; then
        rm -f "$WEB_DIR/$FILE_NAME"
        echo "已删除: $WEB_DIR/$FILE_NAME"
    fi
    
    echo "正在删除API服务器文件..."
    if [ -f "$WEB_DIR/api_server.py" ]; then
        rm -f "$WEB_DIR/api_server.py"
    fi
    
    if [ -f "$WEB_DIR/data.json" ]; then
        read -p "是否删除服务器上的数据文件 (data.json)？[y/N]: " remove_data_choice
        if [[ $remove_data_choice =~ ^[Yy]$ ]]; then
            rm -f "$WEB_DIR/data.json"
            echo "数据文件已删除"
        else
            echo "数据文件已保留"
        fi
    fi
    
    echo ""
    read -p "是否删除Nginx程序文件？[y/N]: " remove_nginx
    if [[ $remove_nginx =~ ^[Yy]$ ]]; then
        echo "正在删除Nginx程序..."
        
        if [ -d "/usr/local/nginx" ]; then
            rm -rf /usr/local/nginx
            echo "已删除: /usr/local/nginx"
        fi
        
        rm -f /usr/local/bin/nginx 2>/dev/null || true
        rm -f /usr/bin/nginx 2>/dev/null || true
        
        if command -v apt-get &> /dev/null; then
            echo "正在卸载通过apt安装的Nginx..."
            apt-get remove -y nginx nginx-common nginx-full 2>/dev/null || true
            apt-get purge -y nginx nginx-common nginx-full 2>/dev/null || true
        elif command -v yum &> /dev/null; then
            echo "正在卸载通过yum安装的Nginx..."
            yum remove -y nginx 2>/dev/null || true
        elif command -v dnf &> /dev/null; then
            echo "正在卸载通过dnf安装的Nginx..."
            dnf remove -y nginx 2>/dev/null || true
        fi
    else
        echo "保留Nginx程序文件"
    fi
    
    echo ""
    echo "=========================================="
    echo "卸载完成！"
    echo "=========================================="
    exit 0
fi

echo ""
echo "=========================================="
echo "  开始安装部署"
echo "=========================================="
echo ""

download_file() {
    local target_path=$1
    local target_dir=$(dirname "$target_path")
    
    if [ ! -d "$target_dir" ]; then
        echo "创建目录: $target_dir"
        mkdir -p "$target_dir"
    fi
    
    echo "正在从GitHub下载文件..."
    if command -v wget &> /dev/null; then
        if wget -q "$GITHUB_URL" -O "$target_path"; then
            if [ -f "$target_path" ] && [ -s "$target_path" ]; then
                echo "文件下载成功"
                return 0
            fi
        fi
    elif command -v curl &> /dev/null; then
        if curl -sL "$GITHUB_URL" -o "$target_path"; then
            if [ -f "$target_path" ] && [ -s "$target_path" ]; then
                echo "文件下载成功"
                return 0
            fi
        fi
    else
        echo "错误：未找到wget或curl，无法下载文件"
        echo "请手动安装: sudo apt install wget 或 sudo yum install wget"
        return 1
    fi
    
    echo "文件下载失败"
    return 1
}

get_file() {
    local target_path=$1
    if [ -f "$CURRENT_DIR/$FILE_NAME" ]; then
        echo "使用本地文件..."
        cp "$CURRENT_DIR/$FILE_NAME" "$target_path"
        return 0
    else
        if download_file "$target_path"; then
            return 0
        else
            return 1
        fi
    fi
}

echo "正在安装Nginx..."
NGINX_INSTALLED=false

if command -v apt-get &> /dev/null; then
    echo "检查Nginx是否已安装..."
    if command -v nginx &> /dev/null && [ -d "/etc/nginx" ]; then
        echo "Nginx已安装，版本: $(nginx -v 2>&1)"
        NGINX_INSTALLED=true
    else
        echo ""
        echo "=========================================="
        echo "从GitHub源码编译安装Nginx"
        echo "=========================================="
        echo ""
        echo "开始从GitHub源码编译安装Nginx..."
        
        BUILD_DIR="/tmp/nginx-build"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"
        
        echo "检查编译依赖..."
        MISSING_DEPS=""
        command -v gcc >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS gcc"
        command -v make >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS make"
        command -v git >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS git"
        
        PCRE_CHECK=false
        if [ -f /usr/include/pcre.h ] || [ -f /usr/local/include/pcre.h ] || [ -f /usr/include/pcre/pcre.h ]; then
            PCRE_CHECK=true
        elif pkg-config --exists libpcre 2>/dev/null || pkg-config --exists libpcre2 2>/dev/null; then
            PCRE_CHECK=true
        fi
        
        if [ "$PCRE_CHECK" = false ]; then
            if command -v apt-get &> /dev/null; then
                MISSING_DEPS="$MISSING_DEPS libpcre3-dev"
            elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                MISSING_DEPS="$MISSING_DEPS pcre-devel"
            fi
        fi

        # 检查OpenSSL头文件
        OPENSSL_CHECK=false
        if [ -f /usr/include/openssl/ssl.h ] || [ -f /usr/local/include/openssl/ssl.h ]; then
            OPENSSL_CHECK=true
        fi
        if [ "$OPENSSL_CHECK" = false ]; then
            if command -v apt-get &> /dev/null; then
                MISSING_DEPS="$MISSING_DEPS libssl-dev"
            elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                MISSING_DEPS="$MISSING_DEPS openssl-devel"
            fi
        fi
        
        if [ -n "$MISSING_DEPS" ]; then
            echo "缺少编译依赖: $MISSING_DEPS"
            echo "尝试自动安装编译依赖..."
            
            if command -v apt-get &> /dev/null; then
                echo "使用apt-get安装编译工具..."
                
                UPDATE_OUTPUT=$(apt-get update 2>&1)
                UPDATE_STATUS=$?
                
                if [ $UPDATE_STATUS -ne 0 ] || echo "$UPDATE_OUTPUT" | grep -q "does not have a Release file\|Unable to locate package"; then
                    echo "软件源有问题，尝试修复..."
                    DEBIAN_VERSION=$(lsb_release -cs 2>/dev/null || echo "buster")
                    
                    if [ -f /etc/apt/sources.list ]; then
                        echo "备份当前sources.list..."
                        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s) 2>/dev/null || true
                        
                        echo "配置archive.debian.org源（用于安装编译工具）..."
                        cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian $DEBIAN_VERSION main
deb http://archive.debian.org/debian $DEBIAN_VERSION-updates main
deb http://archive.debian.org/debian-security $DEBIAN_VERSION/updates main
EOF
                        
                        echo "更新软件包列表..."
                        apt-get update 2>&1 | grep -v "404" | grep -v "Failed" | grep -v "Err:" | grep -v "Ign:" || true
                    fi
                fi
                
                echo "安装编译工具: gcc make git libpcre3-dev zlib1g-dev libssl-dev..."
                INSTALL_OUTPUT=$(apt-get install -y gcc make git libpcre3-dev zlib1g-dev libssl-dev 2>&1)
                INSTALL_STATUS=$?
                
                if [ $INSTALL_STATUS -eq 0 ]; then
                    echo "编译工具安装完成"
                else
                    echo "安装输出: $INSTALL_OUTPUT" | grep -v "404" | grep -v "Failed" | grep -v "Err:" | grep -v "Ign:" || true
                    echo "警告：部分依赖安装可能失败，继续检查..."
                fi
            elif command -v yum &> /dev/null; then
                echo "使用yum安装编译工具..."
                yum install -y gcc make git pcre-devel zlib-devel openssl-devel 2>&1 || {
                    echo "警告：部分依赖安装可能失败，继续尝试..."
                }
            elif command -v dnf &> /dev/null; then
                echo "使用dnf安装编译工具..."
                dnf install -y gcc make git pcre-devel zlib-devel openssl-devel 2>&1 || {
                    echo "警告：部分依赖安装可能失败，继续尝试..."
                }
            else
                echo "未找到包管理器，无法自动安装依赖"
            fi
            
            echo "重新检查编译依赖..."
            MISSING_DEPS=""
            command -v gcc >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS gcc"
            command -v make >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS make"
            command -v git >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS git"
            
            PCRE_CHECK=false
            if [ -f /usr/include/pcre.h ] || [ -f /usr/local/include/pcre.h ] || [ -f /usr/include/pcre/pcre.h ]; then
                PCRE_CHECK=true
            elif pkg-config --exists libpcre 2>/dev/null || pkg-config --exists libpcre2 2>/dev/null; then
                PCRE_CHECK=true
            fi
            
            if [ "$PCRE_CHECK" = false ]; then
                if command -v apt-get &> /dev/null; then
                    MISSING_DEPS="$MISSING_DEPS libpcre3-dev"
                elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                    MISSING_DEPS="$MISSING_DEPS pcre-devel"
                fi
            fi
            
            if [ -n "$MISSING_DEPS" ]; then
                echo "错误：仍缺少编译依赖: $MISSING_DEPS"
                echo "请手动安装这些工具后重新运行脚本"
                echo ""
                echo "安装命令："
                if command -v apt-get &> /dev/null; then
                    echo "  sudo apt-get install -y gcc make git libpcre3-dev zlib1g-dev libssl-dev"
                elif command -v yum &> /dev/null; then
                    echo "  sudo yum install -y gcc make git pcre-devel zlib-devel openssl-devel"
                elif command -v dnf &> /dev/null; then
                    echo "  sudo dnf install -y gcc make git pcre-devel zlib-devel openssl-devel"
                fi
                exit 1
            else
                echo "编译依赖安装成功"
            fi
        else
            echo "编译依赖已满足"
        fi
        
        echo "克隆Nginx源码..."
        if git clone https://github.com/nginx/nginx.git 2>&1; then
            cd nginx
            
            echo "配置编译选项..."
            if auto/configure --prefix=/usr/local/nginx --with-http_ssl_module 2>&1; then
                echo "配置成功（包含SSL模块）"
            else
                echo "尝试不使用SSL模块..."
                if auto/configure --prefix=/usr/local/nginx 2>&1; then
                    echo "配置成功（基础配置）"
                else
                    echo "尝试禁用rewrite模块..."
                    auto/configure --prefix=/usr/local/nginx --without-http_rewrite_module 2>&1 || {
                        echo "配置失败，使用最简配置..."
                        auto/configure --prefix=/usr/local/nginx --without-http_rewrite_module --without-http_ssl_module 2>&1
                    }
                fi
            fi
            
            echo "编译Nginx..."
            if make -j$(nproc 2>/dev/null || echo 1) 2>&1; then
                echo "安装Nginx..."
                make install 2>&1
                
                if [ -f "/usr/local/nginx/sbin/nginx" ]; then
                    echo "创建符号链接..."
                    ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx 2>/dev/null || true
                    ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx 2>/dev/null || true
                    
                    echo "创建必要的目录..."
                    mkdir -p /etc/nginx/conf.d
                    mkdir -p /var/log/nginx
                    mkdir -p /var/cache/nginx
                    
                    echo "创建systemd服务文件..."
                    cat > /etc/systemd/system/nginx.service <<'EOF'
[Unit]
Description=The nginx HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t -c /usr/local/nginx/conf/nginx.conf
ExecStart=/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=process
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
                    
                    systemctl daemon-reload
                    
                    if [ -f "/usr/local/nginx/sbin/nginx" ] || command -v nginx &> /dev/null; then
                        echo "Nginx编译安装成功"
                        NGINX_INSTALLED=true
                    fi
                fi
            else
                echo "编译失败，请检查错误信息"
            fi
            
            cd /
            rm -rf "$BUILD_DIR"
        else
            echo "克隆源码失败，请检查网络连接和git是否安装"
            exit 1
        fi
        
        if [ "$NGINX_INSTALLED" = false ]; then
            echo ""
            echo "=========================================="
            echo "Nginx编译安装失败"
            echo "=========================================="
            echo "请检查："
            echo "1. 网络连接是否正常"
            echo "2. 是否安装了编译工具（gcc, make, git）"
            echo "3. 是否有足够的磁盘空间"
            echo ""
            echo "手动编译安装命令："
            echo "   cd /tmp"
            echo "   git clone https://github.com/nginx/nginx.git"
            echo "   cd nginx"
            echo "   auto/configure --prefix=/usr/local/nginx --with-http_ssl_module"
            echo "   make"
            echo "   sudo make install"
            echo ""
            echo "=========================================="
            exit 1
        fi
    fi
elif command -v yum &> /dev/null; then
    yum install -y nginx
elif command -v dnf &> /dev/null; then
    dnf install -y nginx
else
    echo "错误：未找到包管理器"
    exit 1
fi

echo "确保Web目录存在..."
if [ ! -d "$WEB_DIR" ]; then
    echo "创建Web目录: $WEB_DIR"
    mkdir -p "$WEB_DIR"
fi

echo "获取文件..."
if ! get_file "$WEB_DIR/$FILE_NAME"; then
    echo "错误：无法获取文件"
    echo "请检查网络连接或手动下载文件到: $WEB_DIR/$FILE_NAME"
    exit 1
fi

echo "设置文件权限..."
chown www-data:www-data "$WEB_DIR/$FILE_NAME" 2>/dev/null || chown nginx:nginx "$WEB_DIR/$FILE_NAME" 2>/dev/null || chown root:root "$WEB_DIR/$FILE_NAME" 2>/dev/null || true
chmod 644 "$WEB_DIR/$FILE_NAME"

echo "配置Nginx..."
NGINX_CONF_DIR=""
NGINX_CONF_FILE=""

if [ -d "/usr/local/nginx" ]; then
    echo "检测到从源码安装的Nginx"
    NGINX_CONF_DIR="/usr/local/nginx/conf"
    NGINX_CONF_FILE="/usr/local/nginx/conf/nginx.conf"
    
    if [ ! -f "$NGINX_CONF_FILE" ]; then
        echo "创建Nginx主配置文件..."
        mkdir -p "$NGINX_CONF_DIR"
        
        if [ -f "/usr/local/nginx/conf/mime.types" ]; then
            MIME_TYPES="/usr/local/nginx/conf/mime.types"
        else
            MIME_TYPES="/etc/nginx/mime.types"
            if [ ! -f "$MIME_TYPES" ]; then
                echo "创建mime.types文件..."
                cat > "$MIME_TYPES" <<'MIMETYPES'
types {
    text/html                             html htm shtml;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    application/json                      json;
}
MIMETYPES
            fi
        fi
        
        cat > "$NGINX_CONF_FILE" <<NGINXMAIN
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include $MIME_TYPES;
    default_type application/octet-stream;
    
    sendfile on;
    keepalive_timeout 65;
    
    include $NGINX_CONF_DIR/conf.d/*.conf;
}
NGINXMAIN
        echo "主配置文件已创建: $NGINX_CONF_FILE"
    else
        echo "使用现有配置文件: $NGINX_CONF_FILE"
        if ! grep -q "include.*conf.d" "$NGINX_CONF_FILE" 2>/dev/null; then
            echo "在主配置文件中添加conf.d包含..."
            if grep -q "http {" "$NGINX_CONF_FILE"; then
                sed -i '/http {/a\    include '"$NGINX_CONF_DIR"'/conf.d/*.conf;' "$NGINX_CONF_FILE"
            fi
        fi
        if ! grep -q "include $NGINX_CONF_DIR/conf.d/\*.conf;" "$NGINX_CONF_FILE" 2>/dev/null; then
            perl -0777 -i -pe 's|(http\s*\{)|$1\n    include '"$NGINX_CONF_DIR"'/conf.d/\*.conf;|m' "$NGINX_CONF_FILE"
        fi
    fi
    
    mkdir -p "$NGINX_CONF_DIR/conf.d"
    cat > "$NGINX_CONF_DIR/conf.d/customer-data.conf" <<EOF
server {
    listen $PORT;
    server_name _;
    
    root $WEB_DIR;
    index $FILE_NAME;
    
    location /api/ {
        proxy_pass http://127.0.0.1:7010;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }
    
    location / {
        try_files \$uri \$uri/ /$FILE_NAME;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
    echo "配置文件已创建: $NGINX_CONF_DIR/conf.d/customer-data.conf"

    # 备用端口提供 default1.html
    cat > "$NGINX_CONF_DIR/conf.d/customer-data-7011.conf" <<EOF
server {
    listen $SECONDARY_PORT;
    server_name _;
    
    root $WEB_DIR;
    index $SECONDARY_FILE;
    
    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }
    
    location / {
        try_files \$uri \$uri/ /$SECONDARY_FILE;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
    echo "配置文件已创建: $NGINX_CONF_DIR/conf.d/customer-data-7011.conf"
    
elif [ -d "/etc/nginx" ]; then
    echo "使用系统安装的Nginx"
    NGINX_CONF_DIR="/etc/nginx"
    NGINX_CONF_FILE="/etc/nginx/nginx.conf"
    
    if [ -d "/etc/nginx/sites-available" ]; then
        if [ ! -d "/etc/nginx/sites-enabled" ]; then
            mkdir -p /etc/nginx/sites-enabled
        fi
        cat > /etc/nginx/sites-available/customer-data <<EOF
server {
    listen $PORT;
    server_name _;
    
    root $WEB_DIR;
    index $FILE_NAME;
    
    location /api/ {
        proxy_pass http://127.0.0.1:7010;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }
    
    location / {
        try_files \$uri \$uri/ /$FILE_NAME;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
        ln -sf /etc/nginx/sites-available/customer-data /etc/nginx/sites-enabled/
        echo "配置文件已创建: /etc/nginx/sites-available/customer-data"

        # 备用端口提供 default1.html
        cat > /etc/nginx/sites-available/customer-data-7011 <<EOF
server {
    listen $SECONDARY_PORT;
    server_name _;
    
    root $WEB_DIR;
    index $SECONDARY_FILE;
    
    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }
    
    location / {
        try_files \$uri \$uri/ /$SECONDARY_FILE;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
        ln -sf /etc/nginx/sites-available/customer-data-7011 /etc/nginx/sites-enabled/
        echo "配置文件已创建: /etc/nginx/sites-available/customer-data-7011"
    else
        if [ ! -d "/etc/nginx/conf.d" ]; then
            mkdir -p /etc/nginx/conf.d
        fi
        cat > /etc/nginx/conf.d/customer-data.conf <<EOF
server {
    listen $PORT;
    server_name _;
    
    root $WEB_DIR;
    index $FILE_NAME;
    
    location /api/ {
        proxy_pass http://127.0.0.1:7010;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }
    
    location / {
        try_files \$uri \$uri/ /$FILE_NAME;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
        echo "配置文件已创建: /etc/nginx/conf.d/customer-data.conf"

        # 备用端口提供 default1.html
        cat > /etc/nginx/conf.d/customer-data-7011.conf <<EOF
server {
    listen $SECONDARY_PORT;
    server_name _;
    
    root $WEB_DIR;
    index $SECONDARY_FILE;
    
    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Access-Control-Allow-Origin * always;
    }
    
    location / {
        try_files \$uri \$uri/ /$SECONDARY_FILE;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
        echo "配置文件已创建: /etc/nginx/conf.d/customer-data-7011.conf"
    fi
else
    echo ""
    echo "=========================================="
    echo "错误：未找到Nginx配置目录"
    echo "Nginx未正确安装"
    echo "=========================================="
    exit 1
fi

echo "检查Nginx是否可用..."
NGINX_BIN=""
if command -v nginx &> /dev/null; then
    NGINX_BIN=$(which nginx)
elif [ -f "/usr/local/nginx/sbin/nginx" ]; then
    NGINX_BIN="/usr/local/nginx/sbin/nginx"
    ln -sf "$NGINX_BIN" /usr/local/bin/nginx 2>/dev/null || true
    ln -sf "$NGINX_BIN" /usr/bin/nginx 2>/dev/null || true
fi

if [ -n "$NGINX_BIN" ] || command -v nginx &> /dev/null; then
    if [ -n "$NGINX_BIN" ]; then
        echo "Nginx已安装: $($NGINX_BIN -v 2>&1)"
    else
        echo "Nginx已安装: $(nginx -v 2>&1)"
    fi
    echo "测试Nginx配置..."
    if [ -n "$NGINX_BIN" ]; then
        if $NGINX_BIN -t -c "$NGINX_CONF_FILE" 2>&1; then
            CONFIG_TEST=true
        else
            echo "尝试使用默认配置测试..."
            if $NGINX_BIN -t 2>&1; then
                CONFIG_TEST=true
            else
                CONFIG_TEST=false
            fi
        fi
    else
        if nginx -t -c "$NGINX_CONF_FILE" 2>&1; then
            CONFIG_TEST=true
        else
            if nginx -t 2>&1; then
                CONFIG_TEST=true
            else
                CONFIG_TEST=false
            fi
        fi
    fi
    
    if [ "$CONFIG_TEST" = true ]; then
        echo "Nginx配置测试通过"
    else
        echo "警告：Nginx配置测试失败，但继续部署..."
    fi
    echo "启动Nginx服务..."
    if [ -n "$NGINX_BIN" ] && [ -d "/usr/local/nginx" ]; then
        if pgrep -x nginx > /dev/null; then
            echo "Nginx已在运行，重新加载配置..."
            if [ -f "/etc/systemd/system/nginx.service" ]; then
                systemctl daemon-reload 2>/dev/null || true
                systemctl reload nginx 2>/dev/null || $NGINX_BIN -s reload -c "$NGINX_CONF_FILE" 2>/dev/null || true
            else
                $NGINX_BIN -s reload -c "$NGINX_CONF_FILE" 2>/dev/null || true
            fi
        else
            if [ -f "/etc/systemd/system/nginx.service" ]; then
                systemctl daemon-reload 2>/dev/null || true
                systemctl start nginx 2>/dev/null || $NGINX_BIN -c "$NGINX_CONF_FILE" 2>/dev/null || true
                systemctl enable nginx 2>/dev/null || true
            else
                $NGINX_BIN -c "$NGINX_CONF_FILE" 2>/dev/null || true
            fi
        fi
    else
        if pgrep -x nginx > /dev/null; then
            systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
        else
            systemctl start nginx 2>/dev/null || service nginx start 2>/dev/null || true
            systemctl enable nginx 2>/dev/null || true
        fi
    fi
    
    sleep 2
    
    if pgrep -x nginx > /dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; then
            echo "Nginx服务运行正常，端口 $PORT 已监听"
        else
            echo "Nginx服务运行中，但端口 $PORT 未监听，请检查配置"
        fi
    else
        echo "警告：Nginx服务未运行"
    fi
else
    echo ""
    echo "=========================================="
    echo "错误：Nginx未正确安装"
    echo "=========================================="
    echo "由于软件源问题，Nginx安装失败"
    echo ""
    echo "请手动执行以下命令安装Nginx："
    echo ""
    echo "1. 修复软件源："
    echo "   sudo sed -i 's/mirrors.tencentyun.com/mirrors.aliyun.com/g' /etc/apt/sources.list"
    echo "   sudo sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list"
    echo "   sudo apt-get update"
    echo ""
    echo "2. 安装Nginx："
    echo "   sudo apt-get install -y nginx"
    echo ""
    echo "3. 重新运行部署脚本："
    echo "   sudo bash deploy.sh"
    echo ""
    echo "=========================================="
    exit 1
fi

echo "配置防火墙..."
if command -v ufw &> /dev/null; then
    ufw allow $PORT/tcp
    ufw allow $SECONDARY_PORT/tcp
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=$PORT/tcp
    firewall-cmd --permanent --add-port=$SECONDARY_PORT/tcp
    firewall-cmd --reload
fi

echo ""
echo "✅ Nginx部署完成！"

echo ""
echo "启动API服务器..."
API_PORT="7010"
API_SCRIPT="$WEB_DIR/api_server.py"

if [ ! -f "$API_SCRIPT" ]; then
    echo "创建API服务器脚本..."
    cat > "$API_SCRIPT" <<'APISCRIPT'
#!/usr/bin/env python3

import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import sys

DATA_FILE = '/var/www/html/data.json'
SETTINGS_FILE = '/var/www/html/settings.json'
PASSWORD_FILE = '/var/www/html/password.json'

def read_json_file(filepath, default):
    if os.path.exists(filepath):
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f)
    return default

def write_json_file(filepath, data):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

class APIHandler(BaseHTTPRequestHandler):
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def do_OPTIONS(self):
        self.send_json({}, 200)

    def do_GET(self):
        if self.path == '/api/data':
            try:
                self.send_json(read_json_file(DATA_FILE, []))
            except Exception as e:
                self.send_json({'error': str(e)}, 500)
        elif self.path == '/api/settings':
            try:
                self.send_json(read_json_file(SETTINGS_FILE, {}))
            except Exception as e:
                self.send_json({'error': str(e)}, 500)
        elif self.path == '/api/password':
            try:
                password_data = read_json_file(PASSWORD_FILE, {'password': 'admin', 'version': 0})
                self.send_json({'password': password_data.get('password', 'admin'), 'version': password_data.get('version', 0)})
            except Exception as e:
                self.send_json({'error': str(e)}, 500)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = json.loads(self.rfile.read(content_length).decode('utf-8'))
            if self.path == '/api/data':
                write_json_file(DATA_FILE, post_data)
                self.send_json({'success': True})
            elif self.path == '/api/settings':
                write_json_file(SETTINGS_FILE, post_data)
                self.send_json({'success': True})
            elif self.path == '/api/password':
                password_data = read_json_file(PASSWORD_FILE, {'password': 'admin', 'version': 0})
                password_data['password'] = post_data.get('password', password_data.get('password', 'admin'))
                password_data['version'] = password_data.get('version', 0) + 1
                write_json_file(PASSWORD_FILE, password_data)
                self.send_json({'success': True, 'version': password_data['version']})
            else:
                self.send_response(404)
                self.end_headers()
        except Exception as e:
            self.send_json({'error': str(e)}, 500)

    def log_message(self, format, *args):
        pass

def run(port=7010):
    server_address = ('', port)
    httpd = HTTPServer(server_address, APIHandler)
    print(f'API服务器运行在端口 {port}')
    httpd.serve_forever()

if __name__ == '__main__':
    port = 7010
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    run(port)
APISCRIPT
    chmod +x "$API_SCRIPT"
fi

pkill -f "api_server.py" 2>/dev/null || true
sleep 1

if command -v python3 &> /dev/null; then
    echo "创建API服务器systemd服务..."
    cat > /etc/systemd/system/customer-data-api.service <<EOF
[Unit]
Description=Customer Data API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WEB_DIR
ExecStart=/usr/bin/python3 $API_SCRIPT $API_PORT
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable customer-data-api.service
    systemctl start customer-data-api.service
    sleep 2
    if systemctl is-active --quiet customer-data-api.service; then
        echo "API服务器已启动 (端口 $API_PORT)"
    else
        echo "警告：API服务器启动失败，尝试使用nohup方式启动..."
        nohup python3 "$API_SCRIPT" "$API_PORT" > /dev/null 2>&1 &
        sleep 2
        if pgrep -f "api_server.py" > /dev/null; then
            echo "API服务器已启动 (端口 $API_PORT，nohup方式)"
        else
            echo "警告：API服务器启动失败"
        fi
    fi
else
    echo "警告：未找到python3，无法启动API服务器"
fi

if command -v ufw &> /dev/null; then
    ufw allow $API_PORT/tcp 2>/dev/null || true
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=$API_PORT/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "部署完成！"
echo ""
echo "正在获取服务器IP地址..."

LOCAL_IP=$(hostname -I | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d/ -f1)
fi

PUBLIC_IP=""
if command -v curl &> /dev/null; then
    PUBLIC_IP=$(curl -s --max-time 3 http://ifconfig.me 2>/dev/null || curl -s --max-time 3 http://icanhazip.com 2>/dev/null || curl -s --max-time 3 http://ip.sb 2>/dev/null || echo "")
elif command -v wget &> /dev/null; then
    PUBLIC_IP=$(wget -qO- --timeout=3 http://ifconfig.me 2>/dev/null || wget -qO- --timeout=3 http://icanhazip.com 2>/dev/null || echo "")
fi

echo ""
echo "服务器信息："
if [ -n "$PUBLIC_IP" ]; then
    echo "  公网IP地址: $PUBLIC_IP"
    echo ""
    echo "访问地址: http://$PUBLIC_IP:$PORT/$FILE_NAME"
else
    echo "  无法获取公网IP地址"
    echo ""
    echo "提示：请检查："
    echo "  1. 服务器是否有公网IP"
    echo "  2. 网络连接是否正常"
    echo "  3. 防火墙是否允许访问"
    echo ""
    echo "如果服务器只有内网IP，请使用内网地址访问："
    echo "  http://$LOCAL_IP:$PORT/$FILE_NAME"
fi

echo ""
echo "=========================================="

