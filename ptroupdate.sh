#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Pterodactyl Panel Updater (Pro Edition)
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

pause() {
    echo -e "\n${CYAN}Press [ENTER] to exit...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Pterodactyl Panel Updater "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# 🛡️ INIT & CHECKS
# ==============================================================================
show_banner

if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root! Try running with 'sudo'."
    exit 1
fi

PANEL_DIR="/var/www/pterodactyl"

if [ ! -d "$PANEL_DIR" ]; then
    err "Pterodactyl panel directory not found at $PANEL_DIR"
    exit 1
fi

info "Starting Seamless Panel Update..."

# ==============================================================================
# 🔄 UPDATE PROCESS
# ==============================================================================
step "Navigating to panel directory..."
cd "$PANEL_DIR"
ok "Ready in $PANEL_DIR"

step "Enabling maintenance mode..."
php artisan down >/dev/null 2>&1
ok "Panel is now in maintenance mode."

step "Downloading latest Pterodactyl Panel release..."
curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv >/dev/null 2>&1
ok "Latest version downloaded & extracted."

step "Setting storage permissions..."
chmod -R 755 storage/* bootstrap/cache >/dev/null 2>&1
ok "Permissions updated."

step "Installing/updating Composer dependencies..."
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --quiet
ok "Dependencies installed."

step "Clearing cached views and config..."
php artisan view:clear >/dev/null 2>&1
php artisan config:clear >/dev/null 2>&1
ok "Caches cleared."

step "Running database migrations..."
php artisan migrate --seed --force >/dev/null 2>&1
ok "Migrations completed safely."

step "Correcting file ownership..."
chown -R www-data:www-data "$PANEL_DIR" >/dev/null 2>&1
ok "Ownership set to www-data."

step "Restarting queue workers..."
php artisan queue:restart >/dev/null 2>&1
ok "Queue workers restarted."

step "Disabling maintenance mode..."
php artisan up >/dev/null 2>&1
ok "Panel is back online!"

# ==============================================================================
# 🎉 COMPLETION SCREEN
# ==============================================================================
show_banner
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}              ✨ PANEL UPDATE COMPLETE ✨                       ${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo ""
info "Your Pterodactyl Panel is now running the latest version!"
echo ""
echo -e "${YELLOW}${BOLD}📋 Update Summary:${NC}"
echo -e "  ${GREEN}•${NC} Maintenance mode handled automatically"
echo -e "  ${GREEN}•${NC} Latest panel files deployed"
echo -e "  ${GREEN}•${NC} Permissions & ownership fixed"
echo -e "  ${GREEN}•${NC} Composer dependencies updated"
echo -e "  ${GREEN}•${NC} Caches cleared"
echo -e "  ${GREEN}•${NC} Database migrated safely"
echo -e "  ${GREEN}•${NC} Queue workers restarted"
echo ""
echo -e "${YELLOW}${BOLD}🚀 Next Steps:${NC}"
echo -e "  ${CYAN}•${NC} Visit your panel and verify everything works"
echo -e "  ${CYAN}•${NC} Check the admin area for new features/changelog"
echo -e "  ${CYAN}•${NC} Monitor servers and logs for any issues"
echo ""
echo -e "${MAGENTA}${BOLD}Enjoy the upgraded experience! 🦅✨${NC}"

pause
