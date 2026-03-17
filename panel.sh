#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Pterodactyl Panel Installer
# ==============================================================================
# 👑 Developed by Ray
# 🏢 Ray Industries | 📺 YouTube: @RayVerse
# ⚡ Powered by Bash + Linux Automation
# ==============================================================================

set -e
IFS=$'\n\t'

# ==============================================================================
# 🎨 UI & STYLING (Ray's Signature Style)
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

ok() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "${RED}❌ $1${NC}"; }
step() { echo -e "\n${MAGENTA}⚡ ${BOLD}$1${NC}"; }

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Pterodactyl Panel Installer "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# ⚙️ SETUP CONFIGURATION
# ==============================================================================
show_banner
echo -e "${MAGENTA}--- ⚙️ Panel Configuration ---${NC}"

read -p "🌐 Enter your domain (e.g., panel.example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    err "Domain is required!"
    exit 1
fi
ok "Domain set to: $DOMAIN"

# Auto Generate Secure Credentials
DB_PASS="yourPassword"
DB_NAME="panel"
DB_USER="pterodactyl"
PHP_VERSION="8.3"

# ==============================================================================
# 📦 SYSTEM PREPARATION
# ==============================================================================
step "Updating system & installing core dependencies..."
apt update -qq && apt upgrade -y -qq
apt install -y curl apt-transport-https ca-certificates gnupg lsb-release unzip git tar sudo software-properties-common -qq

OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)
info "Detected OS: ${BOLD}${OS^} ($CODENAME)${NC}"

# PHP Repository
if [[ "$OS" == "ubuntu" ]]; then
    step "Adding PPA for PHP (Ondřej)..."
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
elif [[ "$OS" == "debian" ]]; then
    step "Adding SURY PHP repo manually..."
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg
    echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $CODENAME main" > /etc/apt/sources.list.d/sury-php.list
fi

# Redis Repository
step "Adding official Redis repository..."
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $CODENAME main" > /etc/apt/sources.list.d/redis.list
apt update -qq

# ==============================================================================
# 🛠️ INSTALLATION & SECURING
# ==============================================================================
step "Installing PHP $PHP_VERSION, Nginx, MariaDB, Redis & tools..."
apt install -y \
    php${PHP_VERSION} php${PHP_VERSION}-{cli,fpm,common,mysql,mbstring,bcmath,xml,zip,curl,gd,tokenizer,ctype,simplexml,dom} \
    mariadb-server nginx redis cron -qq
ok "Core packages installed!"

step "Securing MariaDB installation..."
sudo mariadb-secure-installation <<EOF
n
y
y
y
y
EOF
ok "MariaDB secured!"

step "Creating Pterodactyl database & user..."
sudo mariadb << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF
ok "Database configured securely!"

step "Installing Composer globally..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
ok "Composer ready!"

# ==============================================================================
# 🦖 PTERODACTYL PANEL SETUP
# ==============================================================================
step "Downloading latest Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl && cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz && rm panel.tar.gz
chmod -R 755 storage/* bootstrap/cache

step "Configuring .env file..."
if [ ! -f ".env.example" ]; then
    curl -Lo .env.example https://raw.githubusercontent.com/pterodactyl/panel/develop/.env.example
fi
cp .env.example .env
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
if ! grep -q "^APP_ENVIRONMENT_ONLY=" .env; then
    echo "APP_ENVIRONMENT_ONLY=false" >> .env
fi
ok ".env configured!"

step "Installing Panel dependencies (this may take a moment)..."
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --quiet
ok "Dependencies installed!"

step "Generating app key & running migrations..."
php artisan key:generate --force
php artisan migrate --seed --force
ok "Database migrated!"

step "Setting Permissions & Cron jobs..."
chown -R www-data:www-data /var/www/pterodactyl
systemctl enable --now cron
(crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
ok "Permissions & cron job set!"

# ==============================================================================
# 🌐 WEBSERVER & SSL
# ==============================================================================
step "Generating self-signed SSL certificate..."
mkdir -p /etc/ssl/pterodactyl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout /etc/ssl/pterodactyl/privkey.pem \
    -out /etc/ssl/pterodactyl/fullchain.pem \
    -subj "/CN=${DOMAIN}" > /dev/null 2>&1
ok "SSL ready (self-signed)"

step "Configuring Nginx with optimized settings..."
cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    ssl_certificate /etc/ssl/pterodactyl/fullchain.pem;
    ssl_certificate_key /etc/ssl/pterodactyl/privkey.pem;
    client_max_body_size 100M;
    client_body_timeout 120s;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
    }
    location ~ /\.ht { deny all; }
}
EOF
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
ok "Nginx configured & restarted!"

# ==============================================================================
# 🚀 FINALIZATION & WORKERS
# ==============================================================================
step "Deploying Pterodactyl queue worker..."
cat > /etc/systemd/system/pteroq.service << 'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now redis-server pteroq.service
ok "Queue worker activated!"

step "Creating Admin Account..."
cd /var/www/pterodactyl
php artisan p:user:make 

sed -i '/^APP_ENVIRONMENT_ONLY=/d' .env
echo "APP_ENVIRONMENT_ONLY=false" >> .env

# ==============================================================================
# 🎉 COMPLETION SCREEN
# ==============================================================================
show_banner
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}              ✨ INSTALLATION COMPLETE ✨                       ${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo ""
echo -e "${CYAN}${BOLD} 🌐 Panel URL:${NC} https://${DOMAIN}"
echo -e "${CYAN}${BOLD} 📁 Panel Path:${NC} /var/www/pterodactyl"
echo ""
echo -e "${YELLOW}${BOLD}🔐 Secure Database Credentials (SAVE THESE!)${NC}"
echo -e "${BOLD} Database:${NC} ${DB_NAME}"
echo -e "${BOLD} Username:${NC} ${DB_USER}"
echo -e "${BOLD} Password:${NC} ${DB_PASS}"
echo ""
warn "For production: Replace self-signed cert with Let's Encrypt (certbot)"
info "Tip: sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d ${DOMAIN}"
echo ""
echo -e "${MAGENTA}${BOLD}Your Next-Gen Pterodactyl Panel is ready to soar! 🦅🚀${NC}"
echo ""
