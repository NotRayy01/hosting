#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Master Control Center (Pro Edition)
# ==============================================================================
# 👑 Developed by Ray
# 🏢 Ray Industries | 📺 YouTube: @RayVerse
# ==============================================================================

set -e
IFS=$'\n\t'

# ==============================================================================
# 🎨 UI & STYLING
# ==============================================================================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m"
BOLD="\033[1m"

ok() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "${RED}❌ $1${NC}"; }
step() { echo -e "\n${MAGENTA}⚡ ${BOLD}$1${NC}"; }

pause() {
    echo -e "\n${CYAN}Press [ENTER] to return to the Main Menu...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Master Control Center "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

run_remote_script() {
    local target_url="$1"
    local title="$2"

    show_banner
    echo -e "${MAGENTA}--- 📡 Launching: $title ---${NC}"
    step "Fetching script from Ray Industries CDN (GitHub)..."
    
    if command -v curl >/dev/null 2>&1; then
        bash <(curl -sL "$target_url")
        if [ $? -eq 0 ]; then
            echo ""; ok "$title session closed successfully!"
        else
            echo ""; err "An error occurred while running $title."
        fi
    else
        err "curl is not installed on this system."
        info "Please run: sudo apt install curl"
    fi
    pause
}

# ==============================================================================
# 📋 MAIN MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${YELLOW}🎛️  Select a Module to Deploy:${NC}"
    echo ""
    echo "1) 🦖 Pterodactyl Manager (Install, Blueprint, Nebula, Addons)"
    echo "2) 🔮 Reviactyl Manager (Panel Installer & Updater)"
    echo "3) 🖥️  Cloud VM Manager (Creator & Dev Console)"
    echo "4) 🌐 Cloudflare Tunnel Installer"
    echo ""
    echo "0) ❌ Exit Master Control Center"
    echo ""
    
    read -p "Select Option [0-4]: " choice

    case "$choice" in
        1) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager/ptro.sh" "Pterodactyl Manager" ;;
        2) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/reviactyl_manager/reviactyl.sh" "Reviactyl Manager" ;;
        3) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/vm_manager/vm.sh" "VM Manager" ;;
        4) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/other/cloudflare.sh" "Cloudflare Tunnel Installer" ;;
        0)
            show_banner
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo -e "${GREEN}${BOLD}              SESSION TERMINATED                                ${NC}"
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo ""; info "Thank you for using the Ray Master Control Center!"; info "Do not forget to subscribe to @RayVerse! 🚀"; echo ""
            exit 0
            ;;
        *) err "Invalid option! Please enter a number between 0 and 4."; sleep 2 ;;
    esac
done