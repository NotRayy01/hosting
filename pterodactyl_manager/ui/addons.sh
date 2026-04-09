#!/usr/bin/env bash
# ==============================================================================
# 🧩 Ray Blueprint Addon Manager
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

RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"

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
    echo -e "${CYAN}${BOLD} 🧩 Ray Addon Manager "
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo ""
}

# Auto-Detect Panel Directory (Supports both Reviactyl and Pterodactyl)
if [ -d "/var/www/reviactyl/public" ]; then
    PANEL_DIR="/var/www/reviactyl"
elif [ -d "/var/www/pterodactyl/public" ]; then
    PANEL_DIR="/var/www/pterodactyl"
else
    err "No panel installation found! Please install Reviactyl or Pterodactyl first."
    exit 1
fi

ADDONS=(
    "huxregister"
    "loader"
    "mcplugins"
    "minecraftplayermanager"
    "nebula"
    "serverbackgrounds"
    "subdomains"
    "versionchanger"
)

install_addon() {
    local addon_name="$1"
    show_banner
    echo -e "${MAGENTA}--- 🧩 Installing ${addon_name} ---${NC}"
    
    cd "$PANEL_DIR"

    step "Fetching ${addon_name} from Ray Addons Repository..."
    
    # -f makes curl fail silently on 404, preventing it from downloading an HTML error page
    curl -sfL "$RAY_REPO/addons/${addon_name}.blueprint" -o "${addon_name}.blueprint"

    # SAFETY CHECK: Verify the file actually downloaded!
    if [ ! -s "${addon_name}.blueprint" ]; then
        err "Failed to download ${addon_name}.blueprint!"
        info "Make sure the file is uploaded to GitHub at:"
        info "pterodactyl_manager/addons/${addon_name}.blueprint"
        rm -f "${addon_name}.blueprint" # Clean up empty file
        pause; return
    fi
    
    ok "Download successful!"

    step "Executing Blueprint Installer..."
    blueprint -i "${addon_name}"

    ok "Addon ${addon_name} installed successfully!"
    pause
}

install_all() {
    show_banner
    echo -e "${MAGENTA}--- 📦 Bulk Installing All Addons ---${NC}"
    for addon in "${ADDONS[@]}"; do
        install_addon "$addon"
    done
}

install_custom() {
    show_banner
    echo -e "${MAGENTA}--- 🔗 Install Custom Addon ---${NC}"
    read -p "Enter the direct download URL for the .blueprint file: " CUSTOM_URL
    if [ -z "$CUSTOM_URL" ]; then err "URL required!"; pause; return; fi

    # Extract filename from URL
    FILE_NAME=$(basename "$CUSTOM_URL")
    ADDON_NAME="${FILE_NAME%.*}"

    cd "$PANEL_DIR"
    step "Downloading ${FILE_NAME}..."
    curl -sL "$CUSTOM_URL" -o "$FILE_NAME"

    if [ ! -s "$FILE_NAME" ]; then
        err "Download failed or file is empty!"
        rm -f "$FILE_NAME"
        pause; return
    fi

    step "Installing ${ADDON_NAME}..."
    blueprint -i "$ADDON_NAME"
    ok "Custom Addon installed!"
    pause
}

remove_addon() {
    show_banner
    echo -e "${MAGENTA}--- 🗑️  Remove Addon ---${NC}"
    read -p "Enter the exact name of the addon to remove (e.g., huxregister): " REMOVE_NAME
    if [ -z "$REMOVE_NAME" ]; then err "Name required!"; pause; return; fi

    cd "$PANEL_DIR"
    step "Removing ${REMOVE_NAME}..."
    blueprint -remove "$REMOVE_NAME"
    ok "Addon removed!"
    pause
}

# ==============================================================================
# 📋 MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${GREEN}Detected Panel at: $PANEL_DIR${NC}"
    echo ""
    echo -e "${BOLD}--- 📦 Available Addons ---${NC}"
    
    i=1
    for addon in "${ADDONS[@]}"; do
        # Capitalize first letter for display
        display_name="$(tr '[:lower:]' '[:upper:]' <<< ${addon:0:1})${addon:1}"
        echo "$i) 🧩 Install $display_name ($addon)"
        ((i++))
    done

    echo ""
    echo -e "${BOLD}--- 🚀 Bulk Actions ---${NC}"
    echo "A) 📦 Install ALL Detected Addons"
    echo "B) 🔗 Install Custom Addon via URL"
    echo ""
    echo -e "${BOLD}--- 🛑 Danger Zone ---${NC}"
    echo "C) 🗑️  Remove an Addon"
    echo ""
    echo "0) 🔙 Return to Main Menu"
    echo ""
    
    read -p "Select Option: " choice

    case "$choice" in
        [1-8])
            # Array is 0-indexed, so we subtract 1 from the choice
            idx=$((choice-1))
            install_addon "${ADDONS[$idx]}"
            ;;
        [Aa]) install_all ;;
        [Bb]) install_custom ;;
        [Cc]) remove_addon ;;
        0) exit 0 ;;
        *) err "Invalid option!"; sleep 2 ;;
    esac
done
