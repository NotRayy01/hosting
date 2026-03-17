#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Blueprint Installer (Pro Edition)
# ==============================================================================
# 👑 Developed by Ray
# 🏢 Ray Industries | 📺 YouTube: @RayVerse
# ⚡ Powered by Bash + Linux Automation
# ==============================================================================

set -e
IFS=$'\n\t'

# ==============================================================================
# 🌐 GLOBAL VARIABLES
# ==============================================================================
PTERODACTYL_DIRECTORY="/var/www/pterodactyl"

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
    echo -e "\n${CYAN}Press [ENTER] to continue...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Blueprint Installer "
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

# ==============================================================================
# 🏗️ MODULE 1: CLEAN INSTALL
# ==============================================================================
install_blueprint() {
    show_banner
    echo -e "${MAGENTA}--- 🏗️ Clean Install Blueprint ---${NC}"

    step "Installing base dependencies (curl, wget, unzip, git)..."
    apt update -y && apt install -y curl wget unzip ca-certificates git gnupg zip || { err "Dependencies install failed"; return; }
    ok "Base dependencies installed."

    step "Switching to Pterodactyl directory..."
    if [ ! -d "$PTERODACTYL_DIRECTORY" ]; then
        err "Pterodactyl directory not found at $PTERODACTYL_DIRECTORY"
        return
    fi
    cd "$PTERODACTYL_DIRECTORY"
    ok "In $PTERODACTYL_DIRECTORY"

    step "Downloading Blueprint Framework (latest)..."
    local dl_url=$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest | grep 'browser_download_url' | grep 'release.zip' | cut -d '"' -f 4)
    if [ -z "$dl_url" ]; then 
        err "Failed to fetch Blueprint URL from GitHub."
        return
    fi
    
    wget "$dl_url" -O "$PTERODACTYL_DIRECTORY/release.zip"
    unzip -o release.zip || { err "Unzip failed"; return; }
    ok "Blueprint downloaded & extracted."

    step "Installing Node.js 20.x..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

    apt update -y && apt install -y nodejs || { err "Node.js install failed"; return; }
    ok "Node.js installed."

    step "Installing Yarn & Node dependencies..."
    npm i -g yarn || { err "Yarn install failed"; return; }
    yarn install || { err "Yarn dependencies failed"; return; }
    ok "Node dependencies ready."

    step "Creating .blueprintrc configuration..."
    cat <<EOF > "$PTERODACTYL_DIRECTORY/.blueprintrc"
WEBUSER="www-data";
OWNERSHIP="www-data:www-data";
USERSHELL="/bin/bash";
EOF
    ok ".blueprintrc created."

    step "Setting permissions..."
    chmod +x "$PTERODACTYL_DIRECTORY/blueprint.sh" || { err "Permission adjustment failed"; return; }
    chown -R www-data:www-data "$PTERODACTYL_DIRECTORY"
    ok "Permissions fixed."

    step "Launching Blueprint installer..."
    bash "$PTERODACTYL_DIRECTORY/blueprint.sh"

    echo ""
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}           🎉 Blueprint UI Installation Complete!               ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo ""
    info "Panel is breathing... apply a theme and flex! 😏"
    pause
}

# ==============================================================================
# 🔄 MODULE 2: RE-INSTALL (RERUN)
# ==============================================================================
reinstall_blueprint() {
    show_banner
    echo -e "${MAGENTA}--- 🔄 Re-Install Blueprint (Rerun Only) ---${NC}"
    
    if command -v blueprint >/dev/null 2>&1 || [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then
        step "Starting reinstallation..."
        cd "$PTERODACTYL_DIRECTORY"
        blueprint -rerun-install || bash blueprint.sh -rerun-install
        ok "Reinstallation completed!"
    else
        err "Blueprint command not found. Please do a clean install first."
    fi
    pause
}

# ==============================================================================
# ⬆️ MODULE 3: UPDATE BLUEPRINT
# ==============================================================================
update_blueprint() {
    show_banner
    echo -e "${MAGENTA}--- ⬆️ Update Blueprint ---${NC}"
    
    if command -v blueprint >/dev/null 2>&1 || [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then
        step "Starting update..."
        cd "$PTERODACTYL_DIRECTORY"
        blueprint -upgrade || bash blueprint.sh -upgrade
        ok "Update completed successfully!"
    else
        err "Blueprint command not found. Please do a clean install first."
    fi
    pause
}

# ==============================================================================
# 📋 MAIN MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${YELLOW}🔧 Blueprint Framework Manager${NC}"
    echo "1) 🏗️  Clean Install"
    echo "2) 🔄 Re-Install (Rerun Only)"
    echo "3) ⬆️  Update NOW"
    echo "0) ❌ Exit"
    echo ""
    
    read -p "Select an option [0-3]: " choice

    case "$choice" in
        1) install_blueprint ;;
        2) reinstall_blueprint ;;
        3) update_blueprint ;;
        0) 
            show_banner
            ok "Exiting Ray Blueprint Installer. Don't forget to Subscribe to RayVerse! :D"
            exit 0
            ;;
        *) 
            err "Invalid option! Please choose between 0-3."
            sleep 2 
            ;;
    esac
done
