#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Pterodactyl Manager (Mega Edition)
# ==============================================================================
# 👑 Developed by Ray
# 🏢 Ray Industries | 📺 YouTube: @RayVerse
# ⚡ Powered by Bash + Linux Automation
# ==============================================================================

set -e
IFS=$'\n\t'

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m"
BOLD="\033[1m"

RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"
PTRO_DIR="/var/www/pterodactyl"

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
    echo " 🚀 Ray Pterodactyl Manager "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

run_ray_script() {
    local script_path="$1"
    bash <(curl -sL "$RAY_REPO/$script_path")
}

install_both() {
    show_banner
    echo -e "${MAGENTA}--- 🚀 Installing Panel & Wings ---${NC}"
    run_ray_script "ui/panel.sh"
    echo -e "\n${CYAN}➤ Panel installation complete. Proceeding to Wings...${NC}"
    sleep 3
    run_ray_script "ui/wings.sh"
}

install_blueprint() {
    show_banner
    echo -e "${MAGENTA}--- 🏗️ Install Blueprint Framework ---${NC}"
    if [ ! -d "$PTRO_DIR" ]; then err "Pterodactyl Panel is not installed!"; pause; return; fi

    step "Installing Blueprint..."
    cd "$PTRO_DIR"
    bash <(curl -s https://raw.githubusercontent.com/teamblueprint/main/main/blueprint.sh)
    ok "Blueprint Framework Installed!"
    pause
}

# ==============================================================================
# 🌌 NEBULA THEME (Auto-Fetch from Addons Folder)
# ==============================================================================
install_nebula() {
    show_banner
    echo -e "${MAGENTA}--- 🌌 Install Nebula Theme ---${NC}"
    
    if [ ! -d "$PTRO_DIR" ]; then
        err "Pterodactyl Panel is not installed at $PTRO_DIR!"
        pause; return
    fi

    cd "$PTRO_DIR"

    step "Downloading Nebula Blueprint from Ray Addons Repository..."
    if curl -sfL "$RAY_REPO/addons/nebula.blueprint" -o nebula.blueprint; then
        ok "Nebula downloaded successfully!"
    else
        err "Failed to download nebula.blueprint!"
        info "Ensure it is uploaded to: pterodactyl_manager/addons/nebula.blueprint on GitHub."
        pause; return
    fi

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
            pause; return
        fi
    fi

    step "Executing Nebula Blueprint..."
    if blueprint -i nebula.blueprint; then
        ok "Nebula Blueprint executed successfully!"
    else
        err "Blueprint execution failed. Check logs."
        pause; return
    fi

    echo ""
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}           ✨ NEBULA INSTALLATION COMPLETE ✨                   ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}🚀 Next Steps:${NC}"
    echo -e "  ${CYAN}•${NC} Clear cache: ${GREEN}php artisan view:clear && php artisan config:clear${NC}"
    echo -e "  ${CYAN}•${NC} Restart queue: ${GREEN}php artisan queue:restart${NC}"
    echo -e "  ${CYAN}•${NC} Refresh panel in browser (Ctrl+Shift+R)"
    echo ""
    pause
}

# ==============================================================================
# 📋 PTERODACTYL MAIN MENU
# ==============================================================================
while true; do
    show_banner
    echo -e "${YELLOW}🎛️  Pterodactyl Manager Menu${NC}"
    echo ""
    echo -e "${BOLD}--- 📦 Core Installations ---${NC}"
    echo "1) 🖥️  Install Pterodactyl Panel"
    echo "2) 🦅 Install Pterodactyl Wings"
    echo "3) 🚀 Install Both (Panel + Wings automatically)"
    echo "4) 🐘 Install phpMyAdmin (Database Manager)"
    echo ""
    echo -e "${BOLD}--- 🛠️ Customization & Addons ---${NC}"
    echo "5) 🏗️  Install Blueprint Framework"
    echo "6) 🌌 Install Nebula Theme"
    echo "7) 🧩 Manage Blueprint Addons"
    echo ""
    echo -e "${BOLD}--- 🛑 Danger Zone ---${NC}"
    echo "8) 🗑️  Uninstall Pterodactyl System"
    echo ""
    echo "0) ❌ Return to Master Control Center"
    echo ""
    
    read -p "Select Option [0-8]: " choice

    case "$choice" in
        1) run_ray_script "ui/panel.sh" ;;
        2) run_ray_script "ui/wings.sh" ;;
        3) install_both ;;
        4) run_ray_script "installers/phpmyadmin.sh" ;;
        5) install_blueprint ;;
        6) install_nebula ;;
        7) run_ray_script "ui/addons.sh" ;;  <-- Now points to your new addons.sh menu!
        8) run_ray_script "ui/uninstall.sh" ;;
        0) break ;;
        *) err "Invalid option! Please enter a number between 0 and 8."; sleep 2 ;;
    esac
done