#!/usr/bin/env bash
# ==============================================================================
# 🧩 Ray Blueprint Addon Manager (Pro Edition - Auto Detect)
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
API_URL="https://api.github.com/repos/NotRayy01/hosting/contents/pterodactyl_manager/addons"
PTRO_DIR="/var/www/pterodactyl"

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
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo -e "${CYAN}${BOLD} 🧩 Ray Blueprint Addon Manager (Auto-Detect)"
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo ""
}

if [ "$EUID" -ne 0 ]; then err "Run as root!"; exit 1; fi

if ! command -v blueprint >/dev/null 2>&1; then
    err "Blueprint framework is not installed!"
    info "Please install Blueprint from the main menu first."
    pause; exit 1
fi

install_addon_from_repo() {
    local addon_id="$1"
    cd "$PTRO_DIR"
    step "Fetching $addon_id from Ray Addons Repository..."
    
    if curl -sfL "$RAY_REPO/addons/${addon_id}.blueprint" -o "${addon_id}.blueprint"; then
        step "Installing $addon_id..."
        blueprint -install "$addon_id"
        ok "$addon_id installed successfully!"
    else
        err "Could not find ${addon_id}.blueprint in your GitHub addons folder!"
    fi
}

# ==============================================================================
# 📡 AUTO-DETECT ADDONS FROM GITHUB
# ==============================================================================
show_banner
echo -e "${MAGENTA}⚡ Scanning Ray Addons Repository for blueprints...${NC}"

# Fetch file names from GitHub API, filter for .blueprint, and format the names
fetched_addons=$(curl -s "$API_URL" | grep '"name":' | grep '\.blueprint"' | awk -F'"' '{print $4}' | sed 's/\.blueprint//' || true)

if [ -z "$fetched_addons" ]; then
    warn "API rate limit reached or folder empty. Loading fallback list..."
    # Fallback list just in case GitHub blocks the API request
    addon_array=("eggchanger" "huxregister" "mclogs" "mcplugins" "minecraftplayermanager" "serverbackgrounds" "simplefavicons" "simplefooters")
else
    # Read the fetched items into an array
    mapfile -t addon_array <<< "$fetched_addons"
    ok "Found ${#addon_array[@]} addons!"
fi

sleep 1

# ==============================================================================
# 📋 DYNAMIC MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${BOLD}--- 📦 Available Addons ---${NC}"
    
    # Loop through the array and assign numbers automatically
    i=1
    for addon in "${addon_array[@]}"; do
        # Make the output look pretty (capitalize first letter)
        pretty_name=$(echo "$addon" | sed -E 's/([a-z])([A-Z])/\1 \2/g' | awk '{for(j=1;j<=NF;j++)sub(/./,toupper(substr($j,1,1)),$j)}1')
        echo "$i) 🧩 Install $pretty_name ($addon)"
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
    
    read -p "Select Option: " addon_choice

    # Handle dynamic number selection
    if [[ "$addon_choice" =~ ^[0-9]+$ ]] && [ "$addon_choice" -gt 0 ] && [ "$addon_choice" -le "${#addon_array[@]}" ]; then
        idx=$((addon_choice - 1))
        selected_addon="${addon_array[$idx]}"
        install_addon_from_repo "$selected_addon"
        pause
    # Handle static options
    else
        case "${addon_choice^^}" in # ^^ capitalizes input to handle lowercase a,b,c
            A)
                show_banner
                echo -e "${MAGENTA}--- 📦 Installing ALL Addons ---${NC}"
                for addon in "${addon_array[@]}"; do
                    # Skip nebula from bulk install if it accidentally gets in the folder, as it's a theme not an addon
                    if [ "$addon" != "nebula" ]; then
                        install_addon_from_repo "$addon"
                    fi
                done
                echo ""
                ok "Bulk installation complete!"
                pause
                ;;
                
            B)
                echo ""
                read -p "🔗 Enter direct URL to .blueprint file: " ext_url
                read -p "🏷️  Enter Addon identifier: " ext_name
                if [[ -n "$ext_url" && -n "$ext_name" ]]; then
                    cd "$PTRO_DIR"
                    curl -sL "$ext_url" -o "${ext_name}.blueprint"
                    blueprint -install "$ext_name"
                    ok "Custom addon installed!"
                else
                    err "URL and Identifier required."
                fi
                pause
                ;;
                
            C)
                echo ""
                read -p "🏷️  Enter Addon identifier to remove (e.g., eggchanger): " remove_name
                if [ -n "$remove_name" ]; then
                    cd "$PTRO_DIR"
                    blueprint -remove "$remove_name"
                    ok "$remove_name removed!"
                else
                    err "Identifier required."
                fi
                pause
                ;;
                
            0) exit 0 ;;
            *) err "Invalid option."; sleep 2 ;;
        esac
    fi
done