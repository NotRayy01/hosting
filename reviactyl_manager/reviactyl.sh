#!/usr/bin/env bash
# ==============================================================================
# 🔮 Ray Reviactyl Manager (Pro Edition)
# ==============================================================================
# 👑 Developed by Ray | 🏢 Ray Industries
# ==============================================================================

set -e
IFS=$'\n\t'

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
NC="\033[0m"
BOLD="\033[1m"

RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main"

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
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo -e "${CYAN}${BOLD} 🔮 Ray Reviactyl Manager "
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo ""
}

# ==============================================================================
# 1️⃣ INSTALL REVIACTYL
# ==============================================================================
install_reviactyl() {
    show_banner
    echo -e "${MAGENTA}--- 🔮 Install Reviactyl Panel ---${NC}"
    
    if [ -d "/var/www/reviactyl/public" ]; then
        err "Reviactyl is already installed on this server!"
        pause; return
    fi

    # Auto Generate Secure Credentials
    DB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20 ; echo '')
    DB_NAME="reviactyl"
    DB_USER="reviactyl"

    step "Updating system & installing core repositories..."
    apt-get update -qq && apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release -qq
    
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
    
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg --yes
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list >/dev/null

    apt-get update -qq
    ok "Repositories added!"

    step "Installing PHP 8.3, MariaDB, Nginx, Redis & Dependencies..."
    apt-get install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl} mariadb-server nginx tar unzip git redis-server -qq
    
    if ! command -v composer >/dev/null 2>&1; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    ok "Dependencies installed!"

    step "Configuring Database..."
    mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    ok "Database 'reviactyl' configured securely!"

    step "Downloading Reviactyl Panel..."
    mkdir -p /var/www/reviactyl
    cd /var/www/reviactyl
    
    curl -sLo panel.tar.gz https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz >/dev/null 2>&1
    chmod -R 755 storage/* bootstrap/cache/
    rm -f panel.tar.gz
    ok "Reviactyl downloaded and extracted!"

    step "Configuring Environment & Composer..."
    cp .env.example .env
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --quiet
    php artisan key:generate --force
    ok "Environment prepped!"

    step "Initial Panel Setup (Interactive)..."
    echo -e "${YELLOW}Please answer the following prompts to configure your panel:${NC}"
    php artisan p:environment:setup
    
    php artisan p:environment:database --host="127.0.0.1" --port="3306" --database="${DB_NAME}" --username="${DB_USER}" --password="${DB_PASS}"
    
    php artisan p:environment:mail
    
    step "Running Database Migrations..."
    php artisan migrate --seed --force

    step "Creating Admin User..."
    php artisan p:user:make

    step "Setting Permissions & Services..."
    chown -R www-data:www-data /var/www/reviactyl/*
    
    (crontab -l 2>/dev/null | grep -v "/var/www/reviactyl/artisan schedule:run"; echo "* * * * * php /var/www/reviactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

    cat > /etc/systemd/system/reviq.service << EOF
[Unit]
Description=Reviactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/reviactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now redis-server >/dev/null 2>&1
    systemctl enable --now reviq.service >/dev/null 2>&1
    ok "Services started and enabled!"

    echo ""
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}              ✨ REVIACTYL INSTALLATION COMPLETE ✨             ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}🔐 Database Credentials (Saved to .env automatically)${NC}"
    echo -e " Database: ${DB_NAME}"
    echo -e " Username: ${DB_USER}"
    echo -e " Password: ${DB_PASS}"
    echo ""
    info "Next step: Run Option 2 (Webserver Config) from the menu to secure your domain!"
    pause
}

# ==============================================================================
# 2️⃣ WEBSERVER CONFIG
# ==============================================================================
config_webserver() {
    show_banner
    echo -e "${MAGENTA}--- 🌐 Configure Reviactyl Webserver ---${NC}"
    
    read -p "🔗 Enter your Reviactyl FQDN (e.g., panel.domain.com): " FQDN
    if [ -z "$FQDN" ]; then err "Domain required!"; pause; return; fi

    echo -e -n " ${CYAN}➤${NC} Configure with SSL/HTTPS? (y/N): "
    read -r USE_SSL

    step "Fetching Nginx Config from Ray Repository..."
    if [[ "$USE_SSL" =~ [Yy] ]]; then
        curl -sL "$RAY_REPO/pterodactyl_manager/configs/nginx_ssl.conf" -o /etc/nginx/sites-available/reviactyl.conf
    else
        curl -sL "$RAY_REPO/pterodactyl_manager/configs/nginx.conf" -o /etc/nginx/sites-available/reviactyl.conf
    fi

    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-available/reviactyl.conf
    sed -i -e "s@<php_socket>@/run/php/php8.3-fpm.sock@g" /etc/nginx/sites-available/reviactyl.conf
    sed -i -e "s@/var/www/pterodactyl/public@/var/www/reviactyl/public@g" /etc/nginx/sites-available/reviactyl.conf
    sed -i -e "s@/var/log/nginx/pterodactyl.app-error.log@/var/log/nginx/reviactyl.app-error.log@g" /etc/nginx/sites-available/reviactyl.conf

    step "Enabling Configuration..."
    ln -sf /etc/nginx/sites-available/reviactyl.conf /etc/nginx/sites-enabled/reviactyl.conf
    rm -f /etc/nginx/sites-enabled/default

    systemctl restart nginx
    
    if [[ "$USE_SSL" =~ [Yy] ]]; then
        info "Nginx is configured! Ensure you generate your SSL using certbot:"
        info "sudo certbot --nginx -d $FQDN"
    else
        ok "Webserver configured successfully for HTTP!"
    fi
    pause
}

# ==============================================================================
# 3️⃣ UPDATE PANEL
# ==============================================================================
update_reviactyl() {
    show_banner
    echo -e "${MAGENTA}--- 🔄 Update Reviactyl Panel ---${NC}"
    
    if [ ! -d "/var/www/reviactyl" ]; then
        err "Reviactyl does not appear to be installed at /var/www/reviactyl!"
        pause; return
    fi

    echo "1) ⚡ Automatic Upgrade (Reviactyl v2.0.1+ Only)"
    echo "2) 🛠️  Manual Upgrade (For older versions or if Auto fails)"
    echo "0) 🔙 Cancel Update"
    echo ""
    read -p "Select Update Method [0-2]: " update_choice

    cd /var/www/reviactyl

    case "$update_choice" in
        1)
            step "Running Automatic Upgrade..."
            php artisan p:upgrade
            ok "Automatic Upgrade process finished!"
            ;;
        2)
            step "Downloading latest Reviactyl release..."
            curl -sLo panel.tar.gz https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz
            
            step "Extracting files..."
            tar -xzvf panel.tar.gz >/dev/null 2>&1
            chmod -R 755 storage/* bootstrap/cache/
            rm -f panel.tar.gz

            step "Updating Composer Dependencies..."
            export COMPOSER_ALLOW_SUPERUSER=1
            composer install --no-dev --optimize-autoloader --quiet

            step "Running Database Migrations..."
            php artisan migrate --seed --force

            step "Setting Permissions & Restarting Queue..."
            chown -R www-data:www-data /var/www/reviactyl/*
            systemctl restart reviq.service
            
            ok "Manual Upgrade complete!"
            ;;
        0) return ;;
        *) err "Invalid option!"; sleep 2; return ;;
    esac
    pause
}

# ==============================================================================
# 4️⃣ MIGRATE FROM PTERODACTYL
# ==============================================================================
migrate_panel() {
    show_banner
    echo -e "${MAGENTA}--- 🚚 Migrate from Pterodactyl to Reviactyl ---${NC}"
    
    if [ ! -d "/var/www/pterodactyl" ]; then
        err "Pterodactyl installation not found at /var/www/pterodactyl!"
        info "You can only migrate an existing Pterodactyl panel."
        pause; return
    fi

    warn "This will wipe your current Pterodactyl files and replace them with Reviactyl."
    warn "Your database and .env configuration will be preserved."
    echo -e -n " ${CYAN}➤${NC} Are you sure you want to proceed? (y/N): "
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ [Yy] ]]; then
        info "Migration aborted."
        pause; return
    fi

    step "Backing up .env and cleaning old files..."
    cd /var/www/pterodactyl
    cp .env /tmp/pterodactyl_env_backup
    
    # Safely remove all files and folders except the .env file
    find . -mindepth 1 -maxdepth 1 ! -name '.env' -exec rm -rf {} +
    ok "Old files removed safely!"

    step "Downloading Reviactyl Panel..."
    curl -sLo panel.tar.gz https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz
    
    step "Extracting files..."
    tar -xzvf panel.tar.gz >/dev/null 2>&1
    chmod -R 755 storage/* bootstrap/cache/
    rm -f panel.tar.gz

    step "Installing Composer Dependencies..."
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --quiet

    step "Running Database Migrations..."
    php artisan migrate --seed --force

    step "Setting Permissions & Restarting Queue..."
    chown -R www-data:www-data /var/www/pterodactyl/*
    systemctl restart pteroq.service >/dev/null 2>&1 || true
    
    echo ""
    ok "Migration to Reviactyl complete!"
    info "Since you migrated, your panel will still run from /var/www/pterodactyl to keep your webserver happy!"
    pause
}

# ==============================================================================
# 📋 REVIACTYL MENU
# ==============================================================================
while true; do
    show_banner
    echo "1) 🔮 Install Reviactyl Panel (Fresh Install)"
    echo "2) 🌐 Configure Webserver (Nginx)"
    echo "3) 🔄 Update Panel"
    echo "4) 🚚 Migrate from Pterodactyl to Reviactyl"
    echo ""
    echo "0) 🔙 Return to Master Control Center"
    echo ""
    
    read -p "Select Option [0-4]: " choice

    case "$choice" in
        1) install_reviactyl ;;
        2) config_webserver ;;
        3) update_reviactyl ;;
        4) migrate_panel ;;
        0) break ;;
        *) err "Invalid option!"; sleep 2 ;;
    esac
done
