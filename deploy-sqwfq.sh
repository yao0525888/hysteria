#!/bin/bash
set -e
DOMAIN_INPUT="heartbeatmonitor.cloud"
CERT_EMAIL="admin@heartbeatmonitor.cloud"
PROJECT_NAME="activation-system"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env.production"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
get_docker_compose_cmd() {
    if docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}
DOCKER_COMPOSE_CMD="docker-compose"
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
check_dependencies() {
    log_info "检查系统依赖..."
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    log_info "依赖检查通过"
}
check_config() {
    log_info "检查配置文件..."
    if [ ! -f "$ENV_FILE" ]; then
        log_warn "生产环境配置文件 $ENV_FILE 不存在，创建默认配置"
        create_default_env_file
    fi
    required_vars=("JWT_SECRET" "SESSION_SECRET" "ENCRYPTION_KEY" "ADMIN_PASSWORD")
    missing_vars=()
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$ENV_FILE" || grep -q "^${var}=your-" "$ENV_FILE"; then
            missing_vars+=("$var")
        fi
    done
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_warn "以下环境变量需要设置或修改为安全值:"
        for var in "${missing_vars[@]}"; do log_warn "  - $var"; done
        log_warn "请编辑 $ENV_FILE 文件进行配置"
        log_warn "服务将使用默认配置启动，但这不安全"
    else
        log_info "配置文件检查通过"
    fi
}
create_default_env_file() {
    cat > "$ENV_FILE" << 'EOF'
NODE_ENV=production
PORT=7030
ADMIN_PORT=7030
MONGODB_URI=mongodb://admin:password@mongodb:27017/activation_system?authSource=admin
MONGO_ROOT_USERNAME=admin
MONGO_ROOT_PASSWORD=password
JWT_SECRET=your-production-jwt-secret-key-change-this-in-production-32-chars-minimum
JWT_EXPIRES_IN=24h
REFRESH_TOKEN_EXPIRES_IN=7d
SESSION_SECRET=your-production-session-secret-key-change-this-in-production
CORS_ORIGIN=https://yourdomain.com,http://localhost:7030
ENCRYPTION_KEY=your-32-character-encryption-key-for-production-only
ADMIN_USERNAME=admin
ADMIN_PASSWORD=change-this-password-in-production
ADMIN_EMAIL=admin@yourdomain.com
DEFAULT_LICENSE_DURATION=365
MAX_LICENSE_DURATION=3650
LICENSE_CHECK_INTERVAL=3600000
MAX_FILE_SIZE=10485760
UPLOAD_PATH=./uploads
LOG_LEVEL=info
LOG_FILE=./logs/app.log
EOF
    log_info "已创建默认配置文件: $ENV_FILE"
    log_warn "请编辑 $ENV_FILE 文件并修改默认的密码和密钥"
}
create_directories() {
    log_info "创建必要的目录..."
    mkdir -p logs
    mkdir -p uploads
    mkdir -p docker/ssl
    mkdir -p scripts
    chmod 755 logs
    chmod 755 uploads
    log_info "目录创建完成"
}
start_services() {
    log_info "启动服务..."
    $DOCKER_COMPOSE_CMD pull
    $DOCKER_COMPOSE_CMD up -d
    log_info "等待服务启动..."
    sleep 10
    if $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then
        log_info "服务启动成功"
        show_status
    else
        log_error "服务启动失败"
        show_logs
        exit 1
    fi
}
stop_services() {
    log_info "停止服务..."
    $DOCKER_COMPOSE_CMD down
    log_info "服务已停止"
}
restart_services() {
    log_info "重启服务..."
    $DOCKER_COMPOSE_CMD restart
    log_info "服务重启完成"
}
show_logs() {
    log_info "显示服务日志..."
    $DOCKER_COMPOSE_CMD logs -f --tail=100
}
show_status() {
    log_info "服务状态:"
    $DOCKER_COMPOSE_CMD ps
    log_info "服务健康检查:"
    if curl -f http://localhost:7030/health >/dev/null 2>&1; then
        log_info "应用服务正常"
    else
        log_warn "应用服务异常"
    fi
}
backup_data() {
    log_info "备份数据..."
    BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log_info "备份数据库..."
    $DOCKER_COMPOSE_CMD exec -T mongodb mongodump \
        --db activation_system \
        --username admin \
        --password password \
        --authenticationDatabase admin \
        --out /backup
    docker cp "$($DOCKER_COMPOSE_CMD ps -q mongodb)":/backup "$BACKUP_DIR/mongodb"
    log_info "备份上传文件..."
    cp -r uploads "$BACKUP_DIR/"
    log_info "备份日志..."
    cp -r logs "$BACKUP_DIR/"
    log_info "压缩备份文件..."
    tar -czf "${BACKUP_DIR}.tar.gz" -C "$BACKUP_DIR" .
    rm -rf "$BACKUP_DIR"
    log_info "备份完成: ${BACKUP_DIR}.tar.gz"
}
update_app() {
    log_info "更新应用..."
    stop_services
    if [ -d .git ]; then
        log_info "拉取最新代码..."
        git pull origin main
    fi
    log_info "重新构建镜像..."
    $DOCKER_COMPOSE_CMD build --no-cache app
    start_services
    log_info "应用更新完成"
}
clean_cache_logs() {
    log_info "开始清理服务器缓存和日志..."
    local before_space=$(df / | tail -1 | awk '{print $3}')
    local log_files_cleaned=0
    local upload_files_cleaned=0
    local temp_files_cleaned=0
    if [ -d "logs" ]; then
        log_info "清理应用日志文件..."
        log_files_cleaned=$(find logs -name "*.log" -type f -mtime +30 -print -delete 2>/dev/null | wc -l || echo 0)
        find logs -name "*.log.*" -type f -mtime +30 -delete 2>/dev/null || true
        log_info "应用日志清理完成：删除了 $log_files_cleaned 个过期日志文件（保留最近30天的日志）"
    else
        log_info "未找到应用日志目录"
    fi
    if [ -d "uploads" ]; then
        log_info "清理过期上传文件..."
        upload_files_cleaned=$(find uploads -type f -mtime +90 -print -delete 2>/dev/null | wc -l || echo 0)
        log_info "上传文件清理完成：删除了 $upload_files_cleaned 个过期文件（保留最近90天的文件）"
    fi
    log_info "清理系统临时文件..."
    if command -v tmpwatch &> /dev/null; then
        sudo tmpwatch -am 24 /tmp 2>/dev/null || true
        temp_files_cleaned=$(find /tmp -type f -mtime +1 2>/dev/null | wc -l || echo 0)
    elif command -v tmpreaper &> /dev/null; then
        sudo tmpreaper 24h /tmp 2>/dev/null || true
        temp_files_cleaned=$(find /tmp -type f -mtime +1 2>/dev/null | wc -l || echo 0)
    else
        temp_files_cleaned=$(find /tmp -type f -mtime +1 -print -delete 2>/dev/null | wc -l || echo 0)
        find /tmp -type d -empty -mtime +1 -delete 2>/dev/null || true
    fi
    log_info "系统临时文件清理完成：删除了 $temp_files_cleaned 个过期临时文件"
    local docker_containers_cleaned=0
    local docker_images_cleaned=0
    local docker_logs_cleaned=0
    if command -v docker &> /dev/null; then
        log_info "清理Docker缓存..."
        docker_containers_cleaned=$(docker container prune -f 2>/dev/null | grep -o '[0-9]*' | tail -1 || echo 0)
        docker_images_cleaned=$(docker image prune -f 2>/dev/null | grep -o '[0-9]*' | tail -1 || echo 0)
        docker volume prune -f >/dev/null 2>&1
        docker builder prune -f >/dev/null 2>&1
        docker system prune -f >/dev/null 2>&1
        if $DOCKER_COMPOSE_CMD ps -q | grep -q .; then
            log_info "清理Docker容器日志..."
            docker_logs_cleaned=0
            for container in $($DOCKER_COMPOSE_CMD ps -q); do
                if command -v truncate &> /dev/null; then
                    log_file="/var/lib/docker/containers/$(docker inspect --format='{{.Id}}' "$container")/$(docker inspect --format='{{.Id}}' "$container")-json.log"
                    if [ -f "$log_file" ]; then
                        local log_size_before=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
                        sudo truncate -s 0 "$log_file" 2>/dev/null || true
                        docker_logs_cleaned=$((docker_logs_cleaned + 1))
                    fi
                fi
            done
            log_info "Docker容器日志清理完成：清理了 $docker_logs_cleaned 个容器的日志"
        fi
    fi
    local journal_space_saved="0B"
    if [ "$EUID" -eq 0 ]; then
        log_info "清理系统日志..."
        journalctl --vacuum-time=7d 2>/dev/null || true
        if command -v logrotate &> /dev/null; then logrotate -f /etc/logrotate.conf 2>/dev/null || true; fi
        if command -v apt-get &> /dev/null; then apt-get clean 2>/dev/null || true; apt-get autoclean 2>/dev/null || true; fi
        if command -v yum &> /dev/null; then yum clean all 2>/dev/null || true; fi
    fi
    if command -v paccache &> /dev/null; then paccache -rk2 2>/dev/null || true; fi
    local after_space=$(df / | tail -1 | awk '{print $3}')
    local space_saved=$((before_space - after_space))
    log_info "缓存和日志清理完成"
    log_info "=== 清理统计 ==="
    log_info "应用日志文件清理: $log_files_cleaned 个文件"
    log_info "上传文件清理: $upload_files_cleaned 个文件"
    log_info "临时文件清理: $temp_files_cleaned 个文件"
    log_info "Docker容器清理: $docker_containers_cleaned 个"
    log_info "Docker镜像清理: $docker_images_cleaned 个"
    log_info "Docker日志清理: $docker_logs_cleaned 个容器"
    if [ "$space_saved" -gt 0 ]; then
        if [ "$space_saved" -lt 1024 ]; then log_info "磁盘空间节省: ${space_saved}B"
        elif [ "$space_saved" -lt $((1024*1024)) ]; then log_info "磁盘空间节省: $((space_saved/1024))KB"
        elif [ "$space_saved" -lt $((1024*1024*1024)) ]; then log_info "磁盘空间节省: $((space_saved/(1024*1024)))MB"
        else log_info "磁盘空间节省: $((space_saved/(1024*1024*1024)))GB"; fi
    else
        log_info "磁盘空间节省: 0B (系统已很干净)"
    fi
    log_info "当前磁盘使用情况:"
    df -h | head -n 1
    df -h | grep -E "(^Filesystem|/)$"
}
cleanup() {
    log_info "清理Docker资源..."
    $DOCKER_COMPOSE_CMD down
    docker image prune -f
    docker volume prune -f
    docker network prune -f
    log_info "清理完成"
}
install_system() {
    log_info "开始系统安装..."
    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
    if command -v docker &> /dev/null && (command -v docker-compose &> /dev/null || docker compose version &> /dev/null); then
        if $DOCKER_COMPOSE_CMD ps -q 2>/dev/null | grep -q .; then
            log_warn "检测到服务正在运行，请先停止服务"
            read -p "是否要停止现有服务？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then log_error "安装已取消"; exit 1; fi
            stop_services
        fi
    fi
    log_info "安装系统依赖..."
    if command -v apt-get &> /dev/null; then
        sudo rm -f /etc/apt/sources.list.d/docker.list
        sudo rm -f /etc/apt/keyrings/docker.gpg
        sudo apt-get update
        sudo apt-get install -y curl wget git htop vim ca-certificates gnupg lsb-release
        if ! command -v docker &> /dev/null; then
            log_info "安装Docker..."
            log_info "使用官方Docker安装脚本..."
            if curl -fsSL https://get.docker.com | sudo sh; then log_info "Docker安装成功"; else log_error "Docker安装失败，请手动安装Docker"; log_error "手动安装命令: curl -fsSL https://get.docker.com | sh"; exit 1; fi
            sudo systemctl start docker
            sudo systemctl enable docker
            DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        fi
    elif command -v yum &> /dev/null; then
        sudo rm -f /etc/yum.repos.d/docker-ce.repo
        sudo yum update -y
        sudo yum install -y curl wget git htop vim yum-utils
        if ! command -v docker &> /dev/null; then
            log_info "安装Docker..."
            log_info "使用官方Docker安装脚本..."
            if curl -fsSL https://get.docker.com | sudo sh; then log_info "Docker安装成功"; else log_error "Docker安装失败，请手动安装Docker"; log_error "手动安装命令: curl -fsSL https://get.docker.com | sh"; exit 1; fi
            sudo systemctl start docker
            sudo systemctl enable docker
            DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        fi
    elif command -v apk &> /dev/null; then
        sudo apk update
        sudo apk add curl wget git htop vim docker docker-compose
        sudo rc-update add docker default
        sudo service docker start
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
    else
        log_warn "未检测到支持的包管理器，请手动安装Docker和依赖"
        log_warn "需要安装: curl wget git htop vim docker docker-compose"
    fi
    if ! command -v docker &> /dev/null; then log_error "Docker安装失败，请手动安装Docker"; exit 1; fi
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then log_error "Docker Compose安装失败，请手动安装Docker Compose"; exit 1; fi
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then sudo usermod -aG docker "$SUDO_USER"; log_info "已将用户 $SUDO_USER 添加到docker组"; log_warn "请重新登录或运行 'newgrp docker' 以使用Docker"; fi
    log_info "创建系统用户..."
    if ! id -u activation >/dev/null 2>&1; then sudo useradd -r -s /bin/false activation; log_info "创建用户 activation 成功"; else log_info "用户 activation 已存在"; fi
    create_directories
    sudo chown -R activation:activation logs uploads backups 2>/dev/null || true
    log_info "配置系统限制..."
    sudo tee -a /etc/security/limits.conf > /dev/null <<EOF
activation soft nofile 65536
activation hard nofile 65536
EOF
    log_info "创建systemd服务..."
    sudo tee /etc/systemd/system/activation-system.service > /dev/null <<EOF
[Unit]
Description=Activation System Service
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
User=root
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/deploy.sh start
ExecStop=$(pwd)/deploy.sh stop
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    log_info "配置日志轮转..."
    sudo tee /etc/logrotate.d/activation-system > /dev/null <<EOF
$(pwd)/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 activation activation
    postrotate
        $DOCKER_COMPOSE_CMD restart app 2>/dev/null || true
    endscript
}
EOF
    log_info "生成SSL证书..."
    if [ ! -f "docker/ssl/cert.pem" ]; then
        mkdir -p docker/ssl
        openssl req -x509 -newkey rsa:4096 -keyout docker/ssl/key.pem -out docker/ssl/cert.pem -days 365 -nodes -subj "/C=CN/ST=State/L=City/O=Organization/CN=localhost"
        sudo chown -R activation:activation docker/ssl
    fi
    if [ -n "${DOMAIN_INPUT:-}" ] && [ -n "${CERT_EMAIL:-}" ]; then
        log_info "尝试使用 Let's Encrypt 获取证书：$DOMAIN_INPUT"
        HOST_SERVICES=("apache2" "httpd")
        STOPPED_HOST_SERVICES=()
        for svc in "${HOST_SERVICES[@]}"; do
            if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --full --all | grep -q "^${svc}.service"; then
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    log_info "停止宿主机服务 $svc 以释放端口"
                    systemctl stop "$svc" 2>/dev/null || true
                    STOPPED_HOST_SERVICES+=("$svc")
                fi
            fi
        done
    fi
    if [ -f "scripts/init-production.js" ]; then
        log_info "运行数据库初始化..."
        $DOCKER_COMPOSE_CMD exec app node scripts/init-production.js
    fi
    sudo systemctl enable activation-system || true
    log_info "系统安装完成！"
    PUBLIC_IP=""
    if command -v curl >/dev/null 2>&1; then
        PUBLIC_IP=$(curl -fsS https://ifconfig.me 2>/dev/null || curl -fsS https://icanhazip.com 2>/dev/null || curl -fsS https://ipinfo.io/ip 2>/dev/null || true)
    fi
    if [ -z "$PUBLIC_IP" ]; then PUBLIC_IP=$(hostname -I 2>/dev/null | awk '{print $1}'); fi
    if [ -n "$PUBLIC_IP" ]; then log_info "管理后台地址: https://$PUBLIC_IP/admin"; else log_warn "无法检测到公网或本地IP，请检查网络"; log_info "管理后台地址: https://localhost/admin"; fi
    log_info "默认管理员账户: admin / admin123456 (请及时修改密码)"
}
setup_https_certificate() {
    log_info "开始配置HTTPS证书..."
    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
    if ! $DOCKER_COMPOSE_CMD ps | grep -q nginx; then log_error "未找到nginx服务，请先安装系统: $0 install"; exit 1; fi
    if [ -z "$DOMAIN_INPUT" ] || [ "$DOMAIN_INPUT" == "example.com" ]; then log_error "请在脚本头部配置实际的 DOMAIN_INPUT 变量"; exit 1; fi
    PRIMARY_DOMAIN=$(echo "$DOMAIN_INPUT" | awk '{print $1}')
    if $DOCKER_COMPOSE_CMD ps nginx | grep -q "Up"; then $DOCKER_COMPOSE_CMD stop nginx; sleep 5; fi
    log_info "检查80端口可用性..."
    WAIT_PORT=80
    MAX_WAIT=30
    waited=0
    is_port_listening() {
        if command -v ss >/dev/null 2>&1; then ss -ltn "sport = :$1" | grep -q LISTEN 2>/dev/null && return 0 || return 1
        elif command -v lsof >/dev/null 2>&1; then lsof -ti tcp:$1 >/dev/null 2>&1 && return 0 || return 1
        else netstat -tln 2>/dev/null | grep -q ":$1\\b" && return 0 || return 1; fi
    }
    while is_port_listening $WAIT_PORT; do
        if [ $waited -ge $MAX_WAIT ]; then log_warn "端口 $WAIT_PORT 在 $MAX_WAIT 秒内未释放，继续会导致证书申请失败。"; break; fi
        log_info "端口 $WAIT_PORT 正在被占用，等待... (${waited}s)"
        sleep 1
        waited=$((waited + 1))
    done
    if is_port_listening $WAIT_PORT; then
        if command -v lsof >/dev/null 2>&1; then
            PIDS_ON_80=$(lsof -ti tcp:$WAIT_PORT)
            for pid in $PIDS_ON_80; do kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true; done
        fi
        sleep 2
    fi
    HOST_SERVICES=("apache2" "httpd")
    STOPPED_HOST_SERVICES=()
    for svc in "${HOST_SERVICES[@]}"; do
        if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --full --all | grep -q "^${svc}.service"; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then systemctl stop "$svc" 2>/dev/null || true; STOPPED_HOST_SERVICES+=("$svc"); fi
        fi
    done
    log_info "创建ACME验证配置..."
    mkdir -p docker/nginx/conf.d
    cat > docker/nginx/conf.d/acme-challenge.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN_INPUT;
    root /var/www/html;
    location /.well-known/acme-challenge/ {
        alias /var/www/html/.well-known/acme-challenge/;
        try_files \$uri =404;
    }
    location / {
        return 301 https://$PRIMARY_DOMAIN\$request_uri;
    }
}
EOF
    log_info "启动nginx进行ACME验证..."
    $DOCKER_COMPOSE_CMD up -d nginx
    sleep 5
    log_info "开始申请Let's Encrypt证书..."
    CERTBOT_CMD="docker run --rm -v $(pwd)/docker/nginx/html:/var/www/html -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot certonly --webroot -w /var/www/html"
    for d in $DOMAIN_INPUT; do CERTBOT_CMD="$CERTBOT_CMD -d $d"; done
    if [ -n "$CERT_EMAIL" ]; then CERTBOT_CMD="$CERTBOT_CMD -m $CERT_EMAIL --agree-tos"; else CERTBOT_CMD="$CERTBOT_CMD --register-unsafely-without-email --agree-tos"; fi
    CERTBOT_CMD="$CERTBOT_CMD --non-interactive --expand"
    if eval "$CERTBOT_CMD"; then log_info "证书申请成功"; else log_error "证书申请失败，请检查域名DNS解析和80端口访问"; for svc in "${STOPPED_HOST_SERVICES[@]}"; do systemctl start "$svc" 2>/dev/null || true; done; exit 1; fi
    log_info "停止nginx以更新HTTPS配置..."
    $DOCKER_COMPOSE_CMD stop nginx
    log_info "创建HTTPS站点配置..."
    rm -f docker/nginx/conf.d/acme-challenge.conf
    cat > docker/nginx/conf.d/ssl.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN_INPUT;
    location /.well-known/acme-challenge/ {
        alias /var/www/html/.well-known/acme-challenge/;
        try_files \$uri =404;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    listen 443 ssl http2;
    server_name $DOMAIN_INPUT;
    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    location /.well-known/acme-challenge/ {
        alias /var/www/html/.well-known/acme-challenge/;
        try_files \$uri =404;
    }
    location /api/ {
        proxy_pass http://app:7030/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept, Origin, User-Agent, DNT, Cache-Control, X-Mx-ReqToken, Keep-Alive, X-Requested-With, If-Modified-Since" always;
        if (\$request_method = 'OPTIONS') { return 204; }
    }
    location / {
        proxy_pass http://app:7030/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            proxy_pass http://app:7030;
        }
    }
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
    log_info "启动nginx启用HTTPS..."
    $DOCKER_COMPOSE_CMD up -d nginx
    sleep 5
    if $DOCKER_COMPOSE_CMD ps nginx | grep -q "Up"; then log_info "nginx HTTPS配置成功"; else log_error "nginx启动失败，请检查配置"; $DOCKER_COMPOSE_CMD logs nginx; exit 1; fi
    for svc in "${STOPPED_HOST_SERVICES[@]}"; do log_info "恢复宿主服务 $svc"; systemctl start "$svc" 2>/dev/null || true; done
    setup_auto_renewal
}
setup_auto_renewal() {
    log_info "配置并测试自动续签..."
    mkdir -p scripts
    cat > scripts/renew-certs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN_DIR=$(ls -1 /etc/letsencrypt/live/ | grep -v "README" | head -n 1)
LE_LIVE="/etc/letsencrypt/live/${DOMAIN_DIR}"
SSL_TARGET_DIR="${PROJECT_ROOT}/docker/ssl"
LOG_FILE="/var/log/renew-certs.log"
echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Starting cert renewal" >> "${LOG_FILE}"
docker run --rm -v "${PROJECT_ROOT}/docker/nginx/html:/var/www/html" -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot renew --quiet >> "${LOG_FILE}" 2>&1 || true
if [ -f "${LE_LIVE}/fullchain.pem" ] && [ -f "${LE_LIVE}/privkey.pem" ]; then
  mkdir -p "${SSL_TARGET_DIR}"
  cp "${LE_LIVE}/fullchain.pem" "${SSL_TARGET_DIR}/cert.pem"
  cp "${LE_LIVE}/privkey.pem" "${SSL_TARGET_DIR}/key.pem"
  chmod 644 "${SSL_TARGET_DIR}/cert.pem" || true
  chmod 600 "${SSL_TARGET_DIR}/key.pem" || true
  if command -v docker >/dev/null 2>&1; then
    docker restart $(docker ps -q -f name=nginx) >> "${LOG_FILE}" 2>&1 || true
  fi
fi
EOF
    chmod +x scripts/renew-certs.sh || true
    if command -v crontab >/dev/null 2>&1; then
        CRON_CMD="0 3 * * 1 /bin/bash $(pwd)/scripts/renew-certs.sh >> /var/log/renew-certs.log 2>&1"
        (crontab -l 2>/dev/null | grep -F "$CRON_CMD") || (crontab -l 2>/dev/null | grep -v "renew-certs.sh"; echo "$CRON_CMD") | crontab -
        log_info "已确保定时续签任务添加到 crontab"
    fi
    log_info "正在手动触发续签测试..."
    /bin/bash scripts/renew-certs.sh
    log_info "续签任务执行完成"
    log_info "请使用命令查看详细日志: cat /var/log/renew-certs.log"
}
uninstall_system() {
    log_warn "开始系统卸载..."
    log_warn "此操作将删除所有数据和服务，请确认已备份重要数据"
    read -p "确认要完全卸载系统吗？这将删除所有数据！(yes/N): " confirm
    if [ "$confirm" != "yes" ]; then log_error "卸载已取消"; exit 1; fi
    log_info "停止并删除服务..."
    $DOCKER_COMPOSE_CMD down -v --remove-orphans
    log_info "删除Docker镜像..."
    docker rmi $(docker images | grep activation-system | awk '{print $3}') 2>/dev/null || true
    log_info "删除systemd服务..."
    sudo systemctl stop activation-system 2>/dev/null || true
    sudo systemctl disable activation-system 2>/dev/null || true
    sudo rm -f /etc/systemd/system/activation-system.service
    sudo systemctl daemon-reload
    log_info "删除日志轮转配置..."
    sudo rm -f /etc/logrotate.d/activation-system
    log_info "删除系统用户..."
    if id -u activation >/dev/null 2>&1; then sudo userdel activation 2>/dev/null || true; log_info "用户 activation 已删除"; fi
    log_warn "删除应用文件..."
    read -p "是否删除应用文件和数据？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then sudo rm -rf logs uploads backups docker/ssl; log_info "应用文件已删除"; else log_info "保留应用文件"; fi
    log_info "清理系统..."
    docker system prune -f
    log_info "系统卸载完成！"
}
show_menu() {
    echo "=========================================="
    echo "  软件授权与激活系统 - 部署脚本"
    echo "=========================================="
    echo ""
    echo "请选择操作："
    echo "安装与配置:"
    echo " 1完整安装系统"
    echo " 2配置HTTPS证书"
    echo " 3配置并测试自动续签"
    echo "服务管理:"
    echo " 4启动服务"
    echo " 5停止服务"
    echo " 6重启服务"
    echo " 7显示服务状态"
    echo "维护工具:"
    echo " 8显示服务日志"
    echo " 9备份数据"
    echo " 10更新应用"
    echo " 11清理服务器缓存和日志"
    echo " 12清理Docker资源"
    echo "其他:"
    echo " 13完全卸载系统"
    echo " 14显示帮助信息"
    echo " 0退出脚本"
    read -p "请输入选项 [0-14] (默认0): " choice
    choice=${choice:-0}
    echo ""
    case $choice in
        1) main install ;;
        2) main ssl ;;
        3) main renew ;;
        4) main start ;;
        5) main stop ;;
        6) main restart ;;
        7) main status ;;
        8) main logs ;;
        9) main backup ;;
        10) main update ;;
        11) main clean ;;
        12) main cleanup ;;
        13) main uninstall ;;
        14) main help ;;
        0) exit 0 ;;
        *) log_error "无效选项: $choice"; show_menu ;;
    esac
}
show_help() {
    echo "软件授权与激活系统 - 部署脚本"
    echo "使用方法: $0 [命令]"
    echo "可用命令:"
    echo "  install      完整安装系统"
    echo "  ssl          配置HTTPS证书"
    echo "  certificate  配置HTTPS证书"
    echo "  renew        配置并测试自动续签"
    echo "  uninstall    完全卸载系统"
    echo "  start        启动服务"
    echo "  stop         停止服务"
    echo "  restart      重启服务"
    echo "  logs         显示日志"
    echo "  status       显示状态"
    echo "  backup       备份数据"
    echo "  update       更新应用"
    echo "  clean        清理服务器缓存和日志"
    echo "  cleanup      清理资源"
    echo "  menu         显示交互式菜单"
    echo "  help         显示此帮助信息"
}
main() {
    if [ $# -eq 0 ]; then show_menu; return; fi
    case "$1" in
        install)
            if [ "$EUID" -ne 0 ]; then log_error "需要root权限"; exit 1; fi
            install_system
            ;;
        ssl|certificate)
            if [ "$EUID" -ne 0 ]; then log_error "需要root权限"; exit 1; fi
            setup_https_certificate
            ;;
        renew)
            if [ "$EUID" -ne 0 ]; then log_error "需要root权限"; exit 1; fi
            setup_auto_renewal
            ;;
        uninstall)
            if [ "$EUID" -ne 0 ]; then log_error "需要root权限"; exit 1; fi
            uninstall_system
            ;;
        start)
            check_dependencies
            check_config
            create_directories
            start_services
            ;;
        stop) stop_services ;;
        restart) restart_services ;;
        logs) show_logs ;;
        status) show_status ;;
        backup) backup_data ;;
        update) update_app ;;
        clean) clean_cache_logs ;;
        cleanup) cleanup ;;
        menu) show_menu ;;
        help) show_help ;;
        *)
            if [ $# -eq 0 ]; then show_menu; else log_error "未知命令: $1"; show_help; exit 1; fi
            ;;
    esac
}
main "$@"
