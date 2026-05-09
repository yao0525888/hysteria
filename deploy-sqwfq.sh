#!/bin/bash
set -e
PROJECT_NAME="activation-system"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env.production"
DEFAULT_DOMAIN="heartbeatmonitor.cloud"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
get_docker_compose_cmd() {
    if docker compose version &> /dev/null; then echo "docker compose"; else echo "docker-compose"; fi
}
DOCKER_COMPOSE_CMD="docker-compose"
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
check_dependencies() {
    log_info "检查系统依赖..."
    if ! command -v docker &> /dev/null; then log_error "Docker 未安装，请先安装 Docker"; exit 1; fi
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then log_error "Docker Compose 未安装，请先安装 Docker Compose"; exit 1; fi
    log_info "依赖检查通过"
}
check_config() {
    log_info "检查配置文件..."
    if [ ! -f "$ENV_FILE" ]; then log_warn "生产环境配置文件 $ENV_FILE 不存在，创建默认配置"; create_default_env_file; fi
    required_vars=("JWT_SECRET" "SESSION_SECRET" "ENCRYPTION_KEY" "ADMIN_PASSWORD")
    missing_vars=()
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$ENV_FILE" || grep -q "^${var}=your-" "$ENV_FILE"; then missing_vars+=("$var"); fi
    done
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_warn "以下环境变量需要设置或修改为安全值:"
        for var in "${missing_vars[@]}"; do log_warn "  - $var"; done
        log_warn "请编辑 $ENV_FILE 文件进行配置"
    else
        log_info "配置文件检查通过"
    fi
}
create_default_env_file() {
    cat > "$ENV_FILE" << EOF
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
CORS_ORIGIN=https://${DEFAULT_DOMAIN},http://localhost:7030
ENCRYPTION_KEY=your-32-character-encryption-key-for-production-only
ADMIN_USERNAME=admin
ADMIN_PASSWORD=change-this-password-in-production
ADMIN_EMAIL=admin@${DEFAULT_DOMAIN}
DEFAULT_LICENSE_DURATION=365
MAX_LICENSE_DURATION=3650
LICENSE_CHECK_INTERVAL=3600000
MAX_FILE_SIZE=10485760
UPLOAD_PATH=./uploads
LOG_LEVEL=info
LOG_FILE=./logs/app.log
EOF
    log_info "已创建默认配置文件: $ENV_FILE"
}
create_directories() {
    log_info "创建必要的目录..."
    mkdir -p logs uploads docker/ssl
    chmod 755 logs uploads
    log_info "目录创建完成"
}
start_services() {
    log_info "启动服务..."
    $DOCKER_COMPOSE_CMD pull
    $DOCKER_COMPOSE_CMD up -d
    sleep 10
    if $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then show_status; else log_error "服务启动失败"; show_logs; exit 1; fi
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
    if curl -f http://localhost:7030/health >/dev/null 2>&1; then log_info "应用服务正常"; else log_warn "应用服务异常"; fi
}
backup_data() {
    log_info "备份数据..."
    BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    $DOCKER_COMPOSE_CMD exec -T mongodb mongodump --db activation_system --username admin --password password --authenticationDatabase admin --out /backup
    docker cp "$($DOCKER_COMPOSE_CMD ps -q mongodb)":/backup "$BACKUP_DIR/mongodb"
    cp -r uploads logs "$BACKUP_DIR/"
    tar -czf "${BACKUP_DIR}.tar.gz" -C "$BACKUP_DIR" .
    rm -rf "$BACKUP_DIR"
    log_info "备份完成: ${BACKUP_DIR}.tar.gz"
}
update_app() {
    log_info "更新应用..."
    stop_services
    if [ -d .git ]; then git pull origin main; fi
    $DOCKER_COMPOSE_CMD build --no-cache app
    start_services
}
clean_cache_logs() {
    log_info "开始清理服务器缓存和日志..."
    local before_space=$(df / | tail -1 | awk '{print $3}')
    if [ -d "logs" ]; then find logs -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true; find logs -name "*.log.*" -type f -mtime +30 -delete 2>/dev/null || true; fi
    if [ -d "uploads" ]; then find uploads -type f -mtime +90 -delete 2>/dev/null || true; fi
    if command -v tmpwatch &> /dev/null; then sudo tmpwatch -am 24 /tmp 2>/dev/null || true; elif command -v tmpreaper &> /dev/null; then sudo tmpreaper 24h /tmp 2>/dev/null || true; else find /tmp -type f -mtime +1 -delete 2>/dev/null || true; find /tmp -type d -empty -mtime +1 -delete 2>/dev/null || true; fi
    if command -v docker &> /dev/null; then
        docker container prune -f >/dev/null 2>&1 || true
        docker image prune -f >/dev/null 2>&1 || true
        docker volume prune -f >/dev/null 2>&1 || true
        docker builder prune -f >/dev/null 2>&1 || true
        docker system prune -f >/dev/null 2>&1 || true
        if $DOCKER_COMPOSE_CMD ps -q | grep -q .; then
            for container in $($DOCKER_COMPOSE_CMD ps -q); do
                if command -v truncate &> /dev/null; then
                    log_file="/var/lib/docker/containers/$(docker inspect --format='{{.Id}}' "$container")/$(docker inspect --format='{{.Id}}' "$container")-json.log"
                    if [ -f "$log_file" ]; then sudo truncate -s 0 "$log_file" 2>/dev/null || true; fi
                fi
            done
        fi
    fi
    if [ "$EUID" -eq 0 ]; then
        journalctl --vacuum-time=7d 2>/dev/null || true
        if command -v apt-get &> /dev/null; then apt-get clean 2>/dev/null || true; apt-get autoclean 2>/dev/null || true; fi
        if command -v yum &> /dev/null; then yum clean all 2>/dev/null || true; fi
    fi
    local after_space=$(df / | tail -1 | awk '{print $3}')
    local space_saved=$((before_space - after_space))
    log_info "缓存和日志清理完成"
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
        if $DOCKER_COMPOSE_CMD ps -q 2>/dev/null | grep -q .; then stop_services; fi
    fi
    if command -v apt-get &> /dev/null; then
        sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
        sudo apt-get update && sudo apt-get install -y curl wget git htop vim ca-certificates gnupg lsb-release
        if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | sudo sh; sudo systemctl start docker; sudo systemctl enable docker; fi
    elif command -v yum &> /dev/null; then
        sudo rm -f /etc/yum.repos.d/docker-ce.repo
        sudo yum update -y && sudo yum install -y curl wget git htop vim yum-utils
        if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | sudo sh; sudo systemctl start docker; sudo systemctl enable docker; fi
    fi
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then log_error "Docker或Docker Compose安装失败"; exit 1; fi
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then sudo usermod -aG docker "$SUDO_USER"; fi
    if ! id -u activation >/dev/null 2>&1; then sudo useradd -r -s /bin/false activation; fi
    create_directories
    sudo chown -R activation:activation logs uploads backups 2>/dev/null || true
    sudo tee -a /etc/security/limits.conf > /dev/null <<EOF
activation soft nofile 65536
activation hard nofile 65536
EOF
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
    if [ ! -f "docker/ssl/cert.pem" ]; then
        mkdir -p docker/ssl
        openssl req -x509 -newkey rsa:4096 -keyout docker/ssl/key.pem -out docker/ssl/cert.pem -days 365 -nodes -subj "/C=CN/ST=State/L=City/O=Organization/CN=localhost"
        sudo chown -R activation:activation docker/ssl
    fi
    if [ -f "scripts/init-production.js" ]; then $DOCKER_COMPOSE_CMD exec app node scripts/init-production.js; fi
    sudo systemctl enable activation-system || true
    log_info "系统安装完成！"
}
setup_https_certificate() {
    log_info "开始配置HTTPS证书..."
    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
    if ! $DOCKER_COMPOSE_CMD ps | grep -q nginx; then log_error "未找到nginx服务"; exit 1; fi
    read -p "请输入域名（默认: $DEFAULT_DOMAIN）: " DOMAIN_INPUT
    DOMAIN_INPUT=${DOMAIN_INPUT:-$DEFAULT_DOMAIN}
    DOMAIN_INPUT=$(echo "$DOMAIN_INPUT" | xargs)
    PRIMARY_DOMAIN=$(echo "$DOMAIN_INPUT" | awk '{print $1}')
    read -p "请输入证书通知邮箱(可选，回车跳过): " CERT_EMAIL
    CERT_EMAIL=$(echo "$CERT_EMAIL" | xargs)
    if $DOCKER_COMPOSE_CMD ps nginx | grep -q "Up"; then $DOCKER_COMPOSE_CMD stop nginx; sleep 5; fi
    WAIT_PORT=80
    MAX_WAIT=30
    waited=0
    while command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$WAIT_PORT" | grep -q LISTEN 2>/dev/null || command -v lsof >/dev/null 2>&1 && lsof -ti tcp:$WAIT_PORT >/dev/null 2>&1 || netstat -tln 2>/dev/null | grep -q ":$WAIT_PORT\b"; do
        if [ $waited -ge $MAX_WAIT ]; then break; fi
        sleep 1; waited=$((waited + 1))
    done
    if command -v lsof >/dev/null 2>&1; then PIDS_ON_80=$(lsof -ti tcp:$WAIT_PORT) && for pid in $PIDS_ON_80; do kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true; done; fi
    sleep 2
    HOST_SERVICES=("apache2" "httpd")
    STOPPED_HOST_SERVICES=()
    for svc in "${HOST_SERVICES[@]}"; do
        if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --full --all | grep -q "^${svc}.service"; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then systemctl stop "$svc" 2>/dev/null || true; STOPPED_HOST_SERVICES+=("$svc"); fi
        fi
    done
    mkdir -p docker/nginx/conf.d
    cat > docker/nginx/conf.d/acme-challenge.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN_INPUT;
    root /var/www/html;
    location /.well-known/acme-challenge/ { alias /var/www/html/.well-known/acme-challenge/; try_files \$uri =404; }
    location / { return 301 https://$PRIMARY_DOMAIN\$request_uri; }
}
EOF
    $DOCKER_COMPOSE_CMD up -d nginx
    sleep 5
    CERTBOT_CMD="docker run --rm -v $(pwd)/docker/nginx/html:/var/www/html -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot certonly --webroot -w /var/www/html"
    for d in $DOMAIN_INPUT; do CERTBOT_CMD="$CERTBOT_CMD -d $d"; done
    if [ -n "$CERT_EMAIL" ]; then CERTBOT_CMD="$CERTBOT_CMD -m $CERT_EMAIL --agree-tos"; else CERTBOT_CMD="$CERTBOT_CMD --register-unsafely-without-email --agree-tos"; fi
    CERTBOT_CMD="$CERTBOT_CMD --non-interactive --expand"
    eval "$CERTBOT_CMD" || { log_error "证书申请失败"; exit 1; }
    $DOCKER_COMPOSE_CMD stop nginx
    rm -f docker/nginx/conf.d/acme-challenge.conf
    cat > docker/nginx/conf.d/ssl.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN_INPUT;
    return 301 https://\$host\$request_uri;
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
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ { expires 1y; add_header Cache-Control "public, immutable"; proxy_pass http://app:7030; }
    }
    location /health { access_log off; return 200 "healthy\n"; add_header Content-Type text/plain; }
}
EOF
    $DOCKER_COMPOSE_CMD up -d nginx
    sleep 5
    for svc in "${STOPPED_HOST_SERVICES[@]}"; do systemctl start "$svc" 2>/dev/null || true; done
    log_info "HTTPS证书配置完成！访问地址: https://$PRIMARY_DOMAIN"
}
auto_renew_certificate() {
    log_info "开始设置自动续签并立即续签一次..."
    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
    if ! $DOCKER_COMPOSE_CMD ps | grep -q nginx; then log_error "未找到nginx服务"; exit 1; fi
    if [ -f "docker/nginx/conf.d/ssl.conf" ]; then
        DOMAIN_INPUT=$(grep "server_name" docker/nginx/conf.d/ssl.conf | head -n 1 | sed 's/server_name//g' | sed 's/;//g' | xargs)
    fi
    if [ -z "$DOMAIN_INPUT" ]; then
        read -p "请输入域名（默认: $DEFAULT_DOMAIN）: " DOMAIN_INPUT
        DOMAIN_INPUT=${DOMAIN_INPUT:-$DEFAULT_DOMAIN}
        DOMAIN_INPUT=$(echo "$DOMAIN_INPUT" | xargs)
    fi
    PRIMARY_DOMAIN=$(echo "$DOMAIN_INPUT" | awk '{print $1}')
    mkdir -p scripts
    cat > scripts/renew-certs.sh <<EOF
#!/bin/bash
set -e
PROJECT_DIR="$(pwd)"
cd "\$PROJECT_DIR"
if docker compose version &> /dev/null; then DOCKER_COMPOSE_CMD="docker compose"; else DOCKER_COMPOSE_CMD="docker-compose"; fi
if \$DOCKER_COMPOSE_CMD ps nginx | grep -q "Up"; then \$DOCKER_COMPOSE_CMD stop nginx; sleep 5; fi
WAIT_PORT=80
MAX_WAIT=30
waited=0
while command -v ss >/dev/null 2>&1 && ss -ltn "sport = :\$WAIT_PORT" | grep -q LISTEN 2>/dev/null || command -v lsof >/dev/null 2>&1 && lsof -ti tcp:\$WAIT_PORT >/dev/null 2>&1 || netstat -tln 2>/dev/null | grep -q ":\$WAIT_PORT\b"; do
    if [ \$waited -ge \$MAX_WAIT ]; then break; fi
    sleep 1; waited=\$((waited + 1))
done
if command -v lsof >/dev/null 2>&1; then PIDS_ON_80=\$(lsof -ti tcp:\$WAIT_PORT) && for pid in \$PIDS_ON_80; do kill "\$pid" 2>/dev/null || kill -9 "\$pid" 2>/dev/null || true; done; fi
sleep 2
HOST_SERVICES=("apache2" "httpd")
STOPPED_HOST_SERVICES=()
for svc in "\${HOST_SERVICES[@]}"; do
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --full --all | grep -q "^\${svc}.service"; then
        if systemctl is-active --quiet "\$svc" 2>/dev/null; then systemctl stop "\$svc" 2>/dev/null || true; STOPPED_HOST_SERVICES+=("\$svc"); fi
    fi
done
if [ -f "docker/nginx/conf.d/ssl.conf" ]; then mv docker/nginx/conf.d/ssl.conf docker/nginx/conf.d/ssl.conf.bak; fi
cat > docker/nginx/conf.d/acme-challenge.conf <<INNER_EOF
server {
    listen 80;
    server_name $DOMAIN_INPUT;
    root /var/www/html;
    location /.well-known/acme-challenge/ { alias /var/www/html/.well-known/acme-challenge/; try_files \\\$uri =404; }
    location / { return 301 https://$PRIMARY_DOMAIN\\\$request_uri; }
}
INNER_EOF
\$DOCKER_COMPOSE_CMD up -d nginx
sleep 5
CERTBOT_CMD="docker run --rm -v \$(pwd)/docker/nginx/html:/var/www/html -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot certonly --webroot -w /var/www/html --force-renewal"
for d in $DOMAIN_INPUT; do CERTBOT_CMD="\$CERTBOT_CMD -d \$d"; done
CERTBOT_CMD="\$CERTBOT_CMD --register-unsafely-without-email --agree-tos --non-interactive --expand"
eval "\$CERTBOT_CMD" || true
\$DOCKER_COMPOSE_CMD stop nginx
rm -f docker/nginx/conf.d/acme-challenge.conf
if [ -f "docker/nginx/conf.d/ssl.conf.bak" ]; then mv docker/nginx/conf.d/ssl.conf.bak docker/nginx/conf.d/ssl.conf; fi
\$DOCKER_COMPOSE_CMD up -d nginx
sleep 5
for svc in "\${STOPPED_HOST_SERVICES[@]}"; do systemctl start "\$svc" 2>/dev/null || true; done
EOF
    chmod +x scripts/renew-certs.sh
    /bin/bash scripts/renew-certs.sh
    if command -v crontab >/dev/null 2>&1; then
        CRON_CMD="0 3 1 * * /bin/bash $(pwd)/scripts/renew-certs.sh >> $(pwd)/logs/renew-certs.log 2>&1"
        (crontab -l 2>/dev/null | grep -v "renew-certs.sh"; echo "$CRON_CMD") | crontab -
        log_info "已配置自动续签"
    fi
}
uninstall_system() {
    log_warn "开始系统卸载..."
    read -p "确认要完全卸载系统吗？(yes/N): " confirm
    if [ "$confirm" != "yes" ]; then exit 1; fi
    $DOCKER_COMPOSE_CMD down -v --remove-orphans
    docker rmi $(docker images | grep activation-system | awk '{print $3}') 2>/dev/null || true
    sudo systemctl stop activation-system 2>/dev/null || true
    sudo systemctl disable activation-system 2>/dev/null || true
    sudo rm -f /etc/systemd/system/activation-system.service /etc/logrotate.d/activation-system
    sudo systemctl daemon-reload
    if id -u activation >/dev/null 2>&1; then sudo userdel activation 2>/dev/null || true; fi
    read -p "是否删除应用文件和数据？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then sudo rm -rf logs uploads backups docker/ssl; fi
    docker system prune -f
    log_info "系统卸载完成！"
}
show_menu() {
    echo "=========================================="
    echo "  软件授权与激活系统 - 部署脚本"
    echo "=========================================="
    echo "请选择操作："
    echo " 1) 完整安装系统"
    echo " 2) 配置HTTPS证书"
    echo " 3) 自动续签并立即续签一次"
    echo " 4) 启动服务"
    echo " 5) 停止服务"
    echo " 6) 重启服务"
    echo " 7) 显示服务状态"
    echo " 8) 显示服务日志"
    echo " 9) 备份数据"
    echo " 10) 更新应用"
    echo " 11) 清理服务器缓存和日志"
    echo " 12) 清理Docker资源"
    echo " 13) 完全卸载系统"
    echo " 0) 退出"
    read -p "请输入选项: " choice
    case ${choice:-0} in
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
        0) exit 0 ;;
        *) show_menu ;;
    esac
}
main() {
    if [ $# -eq 0 ]; then show_menu; return; fi
    case "$1" in
        install) if [ "$EUID" -ne 0 ]; then exit 1; fi; install_system ;;
        ssl|certificate) if [ "$EUID" -ne 0 ]; then exit 1; fi; setup_https_certificate ;;
        renew) if [ "$EUID" -ne 0 ]; then exit 1; fi; auto_renew_certificate ;;
        uninstall) if [ "$EUID" -ne 0 ]; then exit 1; fi; uninstall_system ;;
        start) check_dependencies; check_config; create_directories; start_services ;;
        stop) stop_services ;;
        restart) restart_services ;;
        logs) show_logs ;;
        status) show_status ;;
        backup) backup_data ;;
        update) update_app ;;
        clean) clean_cache_logs ;;
        cleanup) cleanup ;;
        *) show_menu ;;
    esac
}
main "$@"
