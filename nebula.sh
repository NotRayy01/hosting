#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Nebula Blueprint Installer (Pro Edition)
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
    echo " 🚀 Ray Nebula Blueprint Installer "
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

TARGET_DIR="/var/www/pterodactyl"
TEMP_REPO="/tmp/ray-nebula-temp"

# ==============================================================================
# 🌌 INSTALLATION PROCESS
# ==============================================================================
step "Preparing environment..."
rm -rf "$TEMP_REPO" >/dev/null 2>&1
mkdir -p "$TARGET_DIR"
ok "Environment prepared."

step "Downloading Nebula Blueprint from repository..."
if git clone https://github.com/mahimxyzz/Vps.git "$TEMP_REPO" >/dev/null 2>&1; then
    ok "Repository downloaded!"
else
    err "Failed to clone repository. Check internet or repo URL."
    exit 1
fi

SOURCE_FILE="$TEMP_REPO/nebula.blueprint"

if [ ! -f "$SOURCE_FILE" ]; then
    err "nebula.blueprint not found in repository!"
    rm -rf "$TEMP_REPO"
    exit 1
fi

step "Deploying nebula.blueprint to panel..."
mv "$SOURCE_FILE" "$TARGET_DIR/"
rm -rf "$TEMP_REPO"
ok "Blueprint deployed to $TARGET_DIR and cleanup complete."

step "Checking for Blueprint framework..."
if command -v blueprint >/dev/null 2>&1; then
    ok "Blueprint tool detected!"
else
    warn "Blueprint tool not found. Installing now..."
    curl -sSL https://blueprint.zip/install.sh | bash
    if command -v blueprint >/dev/null 2>&1; then
        ok "Blueprint installed successfully!"
    else
        err "Failed to install Blueprint tool."
        exit 1
    fi
fi

step "Executing Nebula Blueprint (this may take a moment)..."
cd "$TARGET_DIR"

# Run with output visible for user feedback
if blueprint -i nebula.blueprint; then
    ok "Nebula Blueprint executed successfully!"
else
    err "Blueprint execution failed. Check logs or compatibility."
    exit 1
fi

# ==============================================================================
# 🎉 COMPLETION SCREEN
# ==============================================================================
echo ""
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}           ✨ NEBULA INSTALLATION COMPLETE ✨                   ${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo ""
info "Blueprint File: ${TARGET_DIR}/nebula.blueprint"
echo ""
echo -e "${YELLOW}${BOLD}🚀 Next Steps:${NC}"
echo -e "  ${CYAN}•${NC} Clear cache: ${GREEN}php artisan view:clear && php artisan config:clear${NC}"
echo -e "  ${CYAN}•${NC} Restart queue: ${GREEN}php artisan queue:restart${NC}"
echo -e "  ${CYAN}•${NC} Refresh panel in browser (Ctrl+Shift+R for hard refresh)"
echo -e "  ${CYAN}•${NC} Enjoy the stunning Nebula theme!"
echo ""
warn "Always backup your panel before installing extensions!"
echo ""
echo -e "${MAGENTA}${BOLD}Your Pterodactyl Panel now shines with Nebula! 🌌✨${NC}"

pause
