#!/usr/bin/env bash
# ==============================================================================
# 🔮 Ray Reviactyl Blueprint Manager (Pro Edition)
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
    echo -e "${CYAN}${BOLD} 🔮 Ray Reviactyl Blueprint Manager "
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo ""
}

if [ "$EUID" -ne 0 ]; then err "Run as root!"; exit 1; fi

# ==============================================================================
# 📡 AUTO-DETECT INSTALLATION DIRECTORY
# ==============================================================================
if [ -d "/var/www/reviactyl/public" ]; then
    REV_DIR="/var/www/reviactyl"
elif [ -d "/var/www/pterodactyl/public" ]; then
    REV_DIR="/var/www/pterodactyl"
else
    REV_DIR=""
fi

# ==============================================================================
# 1️⃣ CLEAN INSTALL
# ==============================================================================
install_blueprint() {
    show_banner
    echo -e "${MAGENTA}--- 🔮 Clean Install Reviactyl Blueprint ---${NC}"
    
    if [ -z "$REV_DIR" ]; then
        err "Reviactyl installation directory not found!"
        info "Checked /var/www/reviactyl and /var/www/pterodactyl."
        pause; return
    fi

    step "Installing Base Dependencies..."
    apt-get update -qq && apt-get install -y curl wget unzip ca-certificates git gnupg zip -qq
    ok "Dependencies installed."

    step "Downloading Latest Reviactyl Blueprint..."
    cd "$REV_DIR"
    LATEST_URL=$(curl -s https://api.github.com/repos/reviactyl/blueprint/releases/latest | grep 'browser_download_url' | grep 'release.zip' | cut -d '"' -f 4)
    
    if [ -z "$LATEST_URL" ]; then
        err "Failed to fetch download URL from GitHub API. Rate limited?"
        pause; return
    fi
    
    wget -q "$LATEST_URL" -O release.zip
    unzip -oq release.zip
    rm -f release.zip
    ok "Reviactyl Blueprint extracted successfully."

    step "Installing Node.js 20.x..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    apt-get update -qq && apt-get install -y nodejs -qq
    ok "Node.js 20.x configured."

    step "Installing Yarn & Panel Dependencies..."
    npm i -g yarn >/dev/null 2>&1
    yarn install --silent >/dev/null 2>&1
    ok "Node modules ready."

    step "Configuring Blueprint Runtime (.blueprintrc)..."
    cat <<EOF > "$REV_DIR/.blueprintrc"
WEBUSER="www-data";
OWNERSHIP="www-data:www-data";
USERSHELL="/bin/bash";
EOF
    ok "Configuration generated."

    step "Applying Strict Permissions..."
    chmod +x "$REV_DIR/blueprint.sh"
    chown -R www-data:www-data "$REV_DIR"
    ok "Permissions secured."

    step "Executing Reviactyl Blueprint Core Installer..."
    bash "$REV_DIR/blueprint.sh"
    
    echo ""
    ok "Reviactyl Blueprint Framework Installation Complete!"
    pause
}

# ==============================================================================
# 2️⃣ RE-INSTALL (RERUN)
# ==============================================================================
reinstall_blueprint() {
    show_banner
    echo -e "${MAGENTA}--- 🔄 Re-Install Blueprint ---${NC}"
    if [ -z "$REV_DIR" ]; then err "Reviactyl not found!"; pause; return; fi
    if ! command -v blueprint >/dev/null 2>&1; then err "Blueprint is not installed!"; pause; return; fi

    step "Running Blueprint Re-Installer..."
    cd "$REV_DIR"
    blueprint -rerun-install
    ok "Re-installation complete!"
    pause
}

# ==============================================================================
# 3️⃣ UPDATE BLUEPRINT
# ==============================================================================
update_blueprint() {
    show_banner
    echo -e "${MAGENTA}--- ⬆️ Update Blueprint ---${NC}"
    if [ -z "$REV_DIR" ]; then err "Reviactyl not found!"; pause; return; fi
    if ! command -v blueprint >/dev/null 2>&1; then err "Blueprint is not installed!"; pause; return; fi

    step "Fetching Latest Framework Updates..."
    cd "$REV_DIR"
    blueprint -upgrade
    ok "Blueprint updated successfully!"
    pause
}

# ==============================================================================
# 📋 MENU LOOP
# ==============================================================================
while true; do
    show_banner
    if [ -n "$REV_DIR" ]; then
        echo -e "${GREEN}Detected Installation: $REV_DIR${NC}"
    else
        echo -e "${RED}Warning: No Reviactyl installation detected!${NC}"
    fi
    echo ""
    echo -e "${BOLD}--- 🔮 Blueprint Actions ---${NC}"
    echo "1) 🚀 Clean Install Blueprint (Reviactyl Fork)"
    echo "2) 🔄 Re-Install (Fix broken extensions)"
    echo "3) ⬆️ Update Blueprint Framework"
    echo ""
    echo "0) 🔙 Return to Manager"
    echo ""
    
    read -p "Select Option [0-3]: " choice

    case "$choice" in
        1) install_blueprint ;;
        2) reinstall_blueprint ;;
        3) update_blueprint ;;
        0) exit 0 ;;
        *) err "Invalid option!"; sleep 2 ;;
    esac
done
