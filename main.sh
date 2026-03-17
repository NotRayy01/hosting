#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Master Control Center
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

# ==============================================================================
# 🛠️ REMOTE EXECUTION ENGINE
# ==============================================================================
run_remote_script() {
    local target_url="$1"
    local title="$2"

    show_banner
    echo -e "${MAGENTA}--- 📡 Launching: $title ---${NC}"
    step "Fetching script from Ray Industries CDN (GitHub)..."
    
    if command -v curl >/dev/null 2>&1; then
        # Execute the remote script in the current environment
        bash <(curl -sL "$target_url")
        
        # Check if the execution was successful
        if [ $? -eq 0 ]; then
            echo ""
            ok "$title executed successfully!"
        else
            echo ""
            err "An error occurred while running $title."
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
    echo -e "${BOLD}--- 🦖 Pterodactyl Suite ---${NC}"
    echo "1) 📦 Install Pterodactyl Panel"
    echo "2) 🦅 Install Pterodactyl Wings"
    echo "3) 🔄 Update Pterodactyl Panel"
    echo "4) 🗑️  Pterodactyl Uninstaller (Danger Zone)"
    echo "5) 🎛️  Pterodactyl Manager Menu"
    echo "6) 🏗️  Blueprint Framework Installer"
    echo "7) 🌌 Nebula Theme Installer"
    echo ""
    echo -e "${BOLD}--- ☁️  Infrastructure & Tools ---${NC}"
    echo "8) 🖥️  Cloud VM Manager"
    echo "9) ➕ Create Cloud VM / Dev Console"
    echo "10) 🌐 Cloudflared Tunnel Installer"
    echo ""
    echo "0) ❌ Exit Master Control Center"
    echo ""
    
    read -p "Select Option [0-10]: " choice

    case "$choice" in
        1) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/panel.sh" "Pterodactyl Panel Installer" ;;
        2) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/wings.sh" "Pterodactyl Wings Installer" ;;
        3) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/ptroupdate.sh" "Pterodactyl Panel Updater" ;;
        4) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/ptrouninstall" "Pterodactyl Uninstaller" ;;
        5) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/ptro.sh" "Pterodactyl Manager Menu" ;;
        6) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/blueprint.sh" "Blueprint Framework Installer" ;;
        7) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/nebula.sh" "Nebula Theme Installer" ;;
        8) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/vm.sh" "Cloud VM Manager" ;;
        9) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/vmcreate.sh" "Cloud VM Creator" ;;
        10) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/cloudflare.sh" "Cloudflared Installer" ;;
        0)
            show_banner
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo -e "${GREEN}${BOLD}              SESSION TERMINATED                                ${NC}"
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo ""
            info "Thank you for using the Ray Master Control Center!"
            info "Do not forget to subscribe to @RayVerse! 🚀"
            echo ""
            exit 0
            ;;
        *)
            err "Invalid option! Please enter a number between 0 and 10."
            sleep 2
            ;;
    esac
done
