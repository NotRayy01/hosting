#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Reviactyl Manager (Pro Edition)
# ==============================================================================
# 👑 Developed by Ray
# 🏢 Ray Industries | 📺 YouTube: @RayVerse
# ==============================================================================

set -e
IFS=$'\n\t'

# ==============================================================================
# 🎨 UI & STYLING (Ray's Signature Style)
# ==============================================================================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color
BOLD="\033[1m"

ok() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "${RED}❌ $1${NC}"; }
step() { echo -e "\n${MAGENTA}⚡ ${BOLD}$1${NC}"; }

pause() {
    echo -e "\n${CYAN}Press [ENTER] to return to the menu...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Reviactyl Control Center "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# 🛡️ INIT & CHECKS
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}❌ This script must be run as root! Try running with 'sudo'.${NC}"
    exit 1
fi

REV_DIR="/var/www/reviactyl"
# Reviactyl requires PHP 8.1 to resolve composer dependencies cleanly
PHP_VERSION="8.1"

# ==============================================================================
# 📦 MODULE 1: INSTALL REVIACTYL
# ==============================================================================
install_reviactyl() {
    show_banner
    echo -e "${MAGENTA}--- 📦 Install Reviactyl Panel ---${NC}"
    
    read -p "🌐 Enter your domain (e.g., rev.example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then err "Domain is required!"; pause; return; fi
    
    # Auto Generate Secure Credentials
    DB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20 ; echo '')
    DB_NAME="reviactyl"
    DB_USER="reviactyl_user"

    step "Updating system & installing core dependencies..."
    apt-get update -qq && apt-get upgrade -y -qq
    apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release unzip git tar sudo software-properties-common -qq

    OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -cs)

    # PHP Repository
    if [[ "$OS" == "ubuntu" ]]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
    elif [[ "$OS" == "debian" ]]; then
        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg --yes
        echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $CODENAME main" > /etc/apt/sources.list.d/sury-php.list
    fi

    # Redis Repository
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg --yes
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $CODENAME main" > /etc/apt/sources.list.d/redis.list
    apt-get update -qq

    step "Installing PHP $PHP_VERSION, Nginx, MariaDB, Redis & tools..."
    apt-get install -y php${PHP_VERSION} php${PHP_VERSION}-{cli,fpm,common,mysql,mbstring,bcmath,xml,zip,curl,gd,tokenizer,ctype,simplexml,dom} mariadb-server nginx redis cron -qq
    
    # Force system to use PHP 8.1 in case 8.3 was previously installed
    update-alternatives --set php /usr/bin/php${PHP_VERSION} >/dev/null 2>&1 || true

    if ! command -v composer >/dev/null 2>&1; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    ok "Core packages installed."

    step "Creating Reviactyl database & user..."
    mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    ok "Database configured securely!"

    step "Downloading Reviactyl Panel..."
    rm -rf "$REV_DIR"
    git clone https://github.com/reviactyl/reviactyl.git "$REV_DIR" -q
    cd "$REV_DIR"
    chmod -R 755 storage/* bootstrap/cache/
    ok "Reviactyl downloaded!"

    step "Configuring Environment..."
    cp .env.example .env
    
    export COMPOSER_ALLOW_SUPERUSER=1
    # Adding ignore-platform-reqs forces composer to ignore strict PHP mismatches
    composer install --no-dev --optimize-autoloader --quiet --ignore-platform-reqs || composer update --no-dev --optimize-autoloader --quiet --ignore-platform-reqs

    php artisan key:generate --force

    sed -i \
        -e "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" \
        -e "s|DB_HOST=.*|DB_HOST=127.0.0.1|g" \
        -e "s|DB_PORT=.*|DB_PORT=3306|g" \
        -e "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" \
        -e "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" \
        -e "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" \
        -e "s|APP_ENV=.*|APP_ENV=production|g" \
        -e "s|APP_DEBUG=.*|APP_DEBUG=false|g" \
        .env

    step "Running Migrations & Seeding..."
    php artisan migrate --seed --force

    step "Setting Permissions & Cron Jobs..."
    chown -R www-data:www-data "$REV_DIR"
    systemctl enable --now cron
    (crontab -l 2>/dev/null | grep -v "$REV_DIR/artisan schedule:run"; echo "* * * * * php $REV_DIR/artisan schedule:run >> /dev/null 2>&1") | crontab -

    step "Generating self-signed SSL & Configuring Nginx..."
    mkdir -p /etc/ssl/reviactyl
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout /etc/ssl/reviactyl/privkey.pem \
        -out /etc/ssl/reviactyl/fullchain.pem \
        -subj "/CN=${DOMAIN}" > /dev/null 2>&1

    cat > /etc/nginx/sites-available/reviactyl.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root ${REV_DIR}/public;
    index index.php;
    ssl_certificate /etc/ssl/reviactyl/fullchain.pem;
    ssl_certificate_key /etc/ssl/reviactyl/privkey.pem;
    client_max_body_size 100M;
    client_body_timeout 120s;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
    }
    location ~ /\.ht { deny all; }
}
EOF
    ln -sf /etc/nginx/sites-available/reviactyl.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx

    step "Deploying Reviactyl Queue Worker..."
    cat > /etc/systemd/system/reviactylq.service << EOF
[Unit]
Description=Reviactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5
ExecStart=/usr/bin/php ${REV_DIR}/artisan queue:work --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now reviactylq.service

    step "Create your Admin Account:"
    cd "$REV_DIR"
    php artisan p:user:make

    echo ""
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}              ✨ REVIACTYL INSTALLATION COMPLETE ✨             ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo ""
    echo -e "${CYAN}${BOLD} 🌐 Panel URL:${NC} https://${DOMAIN}"
    echo -e "${CYAN}${BOLD} 📁 Panel Path:${NC} $REV_DIR"
    echo ""
    echo -e "${YELLOW}${BOLD}🔐 Secure Database Credentials (SAVE THESE!)${NC}"
    echo -e "${BOLD} Database:${NC} ${DB_NAME}"
    echo -e "${BOLD} Username:${NC} ${DB_USER}"
    echo -e "${BOLD} Password:${NC} ${DB_PASS}"
    echo ""
    warn "For production: Replace self-signed cert with Let's Encrypt (certbot)"
    info "Tip: sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d ${DOMAIN}"
    pause
}

# ==============================================================================
# 🔄 MODULE 2: UPDATE REVIACTYL
# ==============================================================================
update_reviactyl() {
    show_banner
    echo -e "${MAGENTA}--- 🔄 Update Reviactyl Panel ---${NC}"
    
    if [ ! -d "$REV_DIR" ]; then
        err "Reviactyl directory not found at $REV_DIR"
        pause; return
    fi

    step "Navigating to panel directory..."
    cd "$REV_DIR"

    step "Enabling maintenance mode..."
    php artisan down >/dev/null 2>&1 || true

    step "Pulling latest Reviactyl files from GitHub..."
    git pull origin main -q

    step "Setting storage permissions..."
    chmod -R 755 storage/* bootstrap/cache >/dev/null 2>&1

    step "Updating Composer dependencies..."
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --quiet --ignore-platform-reqs || composer update --no-dev --optimize-autoloader --quiet --ignore-platform-reqs

    step "Clearing cached views and config..."
    php artisan view:clear >/dev/null 2>&1
    php artisan config:clear >/dev/null 2>&1

    step "Running database migrations..."
    php artisan migrate --seed --force >/dev/null 2>&1

    step "Correcting file ownership..."
    chown -R www-data:www-data "$REV_DIR" >/dev/null 2>&1

    step "Restarting queue workers..."
    systemctl restart reviactylq.service >/dev/null 2>&1 || php artisan queue:restart >/dev/null 2>&1

    step "Disabling maintenance mode..."
    php artisan up >/dev/null 2>&1

    echo ""
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}              ✨ REVIACTYL UPDATE COMPLETE ✨                   ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo ""
    info "Your Reviactyl Panel is now running the latest version!"
    pause
}

# ==============================================================================
# 📋 MAIN MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${YELLOW}🎛️  Reviactyl Manager Menu${NC}"
    echo "1) 📦 Install Reviactyl Panel"
    echo "2) 🔄 Update Reviactyl Panel"
    echo "0) ❌ Exit"
    echo ""
    
    read -p "Select Option [0-2]: " choice

    case "$choice" in
        1) install_reviactyl ;;
        2) update_reviactyl ;;
        0)
            show_banner
            ok "Exiting Reviactyl Manager."
            exit 0
            ;;
        *)
            err "Invalid option! Please enter 0, 1, or 2."
            sleep 2
            ;;
    esac
done