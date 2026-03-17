#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Pterodactyl Hosting Manager
# ==============================================================================
# 👑 Developed by Ray
# 🏢 Ray Industries | 📺 YouTube: @RayVerse
# ⚡ Powered by Bash + Linux Automation
# ==============================================================================

set -euo pipefail
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
    echo -e "\n${CYAN}Press [ENTER] to continue...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Pterodactyl Control Center "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# 🛠️ REMOTE SCRIPT EXECUTION
# ==============================================================================
run_remote_script() {
    local url="$1"
    local name="$2"
    show_banner
    echo -e "${MAGENTA}--- 📥 $name ---${NC}"
    
    step "Downloading and executing remote script..."
    local temp_script=$(mktemp)
    
    if curl -fsSL "$url" -o "$temp_script"; then
        chmod +x "$temp_script"
        bash "$temp_script"
        rm -f "$temp_script"
        echo ""
        ok "$name completed successfully!"
    else
        err "Failed to download script from $url"
    fi
    pause
}

# ==============================================================================
# 📋 MAIN MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${YELLOW}🎛️  Pterodactyl Manager${NC}"
    echo "1) 📦 Panel Installation"
    echo "2) 🦅 Wings Installation"
    echo "3) 🔄 Panel Update"
    echo "4) 🗑️  Uninstall Tools"
    echo "5) 🏗️  Blueprint Setup"
    echo "6) ☁️  Cloudflare Setup"
    echo "7) 🎨 Change Theme"
    echo "8) 🔒 Tailscale (Install + Up)"
    echo "9) 🎮 Minecraft Player Manager"
    echo "10) 🚀 Jexactyl Migration (Full Panel)"
    echo "0) ❌ Exit Manager"
    echo ""
    
    read -p "Select option [0-10]: " choice

    case "$choice" in
        1) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/panel.sh" "PANEL INSTALLATION" ;;
        2) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/wings.sh" "WINGS INSTALLATION" ;;
        3) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/ptroupdate.sh" "PANEL UPDATE" ;;
        4) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/ptrouninstall" "UNINSTALL TOOLS" ;;
        5) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/blueprint.sh" "BLUEPRINT SETUP" ;;
        6) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/cloudflare.sh" "CLOUDFLARE SETUP" ;;
        7) run_remote_script "https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/nebula.sh" "THEME CHANGER" ;;
        
        8)
            show_banner
            echo -e "${MAGENTA}--- 🔒 Tailscale Installation ---${NC}"
            step "Installing Tailscale..."
            curl -fsSL https://tailscale.com/install.sh | sh
            ok "Tailscale installed!"
            systemctl enable --now tailscaled 2>/dev/null || true
            
            step "Bringing Tailscale online..."
            if [ -n "${TS_AUTH_KEY:-}" ]; then
                sudo tailscale up -ssh --auth-key="$TS_AUTH_KEY" && ok "Authenticated via key"
            else
                sudo tailscale up -ssh && ok "Connected! Approve in admin console"
            fi
            pause
            ;;
            
        9)
            show_banner
            echo -e "${MAGENTA}--- 🎮 Minecraft Player Manager ---${NC}"
            step "Installing Minecraft extensions..."
            if [ ! -d "/var/www/pterodactyl" ]; then
                err "Panel directory not found! (/var/www/pterodactyl)"
                pause
                continue
            fi
            cd /var/www/pterodactyl
            
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/minecraftplayermanager.blueprint
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/mcplugins.blueprint
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/huxregister.blueprint
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/mclogs.blueprint
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/eggchanger.blueprint
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/serverbackgrounds.blueprint
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/simplefavicons.blueprint
            wget -q https://github.com/NotRayy01/hosting/raw/refs/heads/main/blueprintaddon/simplefooters.blueprint
            
            blueprint -i mcplugins.blueprint && ok "MC Plugins installed"
            blueprint -i minecraftplayermanager.blueprint && ok "Player Manager installed"
            blueprint -i huxregister.blueprint && ok "Huxregister installed"
            blueprint -i mclogs.blueprint && ok "MC Logs installed"
            blueprint -i eggchanger.blueprint && ok "EGG Changer installed"
            blueprint -i serverbackgrounds.blueprint && ok "Server Backgrounds installed"
            blueprint -i simplefavicons.blueprint && ok "Simple Favicons installed"
            blueprint -i simplefooters.blueprint && ok "Simple Footers installed"
            
            pause
            ;;
            
        10)
            show_banner
            echo -e "${MAGENTA}--- 🚀 Jexactyl Full Panel Migration ---${NC}"
            
            echo -e "${RED}${BOLD}================================================================${NC}"
            echo -e "${RED}${BOLD}                       CRITICAL WARNING                         ${NC}"
            echo -e "${RED}${BOLD} This will COMPLETELY OVERWRITE your Pterodactyl panel          ${NC}"
            echo -e "${RED}${BOLD} with the full Jexactyl panel (billing, ticketing, etc.).       ${NC}"
            echo -e "${RED}${BOLD} THIS ACTION IS NOT REVERSIBLE WITHOUT A BACKUP!                ${NC}"
            echo -e "${RED}${BOLD}================================================================${NC}"
            echo ""
            
            while true; do
                echo -e "${YELLOW}To continue the migration, type 'yes' exactly and press Enter:${NC}"
                read -r confirmation
                if [[ "$confirmation" == "yes" ]]; then
                    break
                else
                    err "Incorrect confirmation. You typed: '${confirmation:-<empty>}'"
                    info "Migration cancelled. Returning to menu..."
                    pause
                    continue 2
                fi
            done
            
            step "Navigating to panel directory..."
            if [ ! -d "/var/www/pterodactyl" ]; then
                err "Panel directory not found! (/var/www/pterodactyl)"
                pause
                continue
            fi
            cd /var/www/pterodactyl
            
            step "Placing panel in maintenance mode..."
            php artisan down || { err "Failed to enable maintenance mode."; pause; continue; }
            
            step "Downloading latest stable Jexactyl release (v3.7.4)..."
            curl -L -o panel.tar.gz https://github.com/jexactyl/jexactyl/releases/download/v3.7.4/panel.tar.gz || {
                err "Download failed. Check internet or GitHub status."
                php artisan up
                pause; continue
            }
            
            step "Extracting and replacing files..."
            tar -xzvf panel.tar.gz >/dev/null && rm -f panel.tar.gz || {
                err "Failed to extract archive."
                rm -f panel.tar.gz 2>/dev/null
                php artisan up
                pause; continue
            }
            
            step "Setting storage and cache permissions..."
            chmod -R 755 storage/* bootstrap/cache
            
            step "Updating Composer dependencies..."
            composer require asbiin/laravel-webauthn --no-interaction 2>/dev/null || info "WebAuthn package skipped (usually not needed)."
            composer install --no-dev --optimize-autoloader --no-interaction || {
                err "Composer installation failed."
                php artisan up
                pause; continue
            }
            
            step "Clearing application caches..."
            php artisan optimize:clear
            
            step "Running database migrations & seeding..."
            php artisan migrate --seed --force || {
                err "Database migration failed! Restore backup ASAP!"
                php artisan up
                pause; continue
            }
            
            step "Fixing webserver ownership (www-data)..."
            chown -R www-data:www-data /var/www/pterodactyl/* 2>/dev/null || info "Ownership fix skipped (manual chown if needed)."
            
            step "Restarting queue workers..."
            php artisan queue:restart
            
            step "Bringing panel back online..."
            php artisan up
            
            echo ""
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo -e "${GREEN}${BOLD}              JEXACTYL MIGRATION SUCCESSFUL!                    ${NC}"
            echo -e "${GREEN}${BOLD} Your panel is now running Jexactyl v3.7.4 (latest stable)      ${NC}"
            echo -e "${GREEN}${BOLD} Enjoy billing, ticketing, improved UI & many more features!    ${NC}"
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo ""
            info "➜ Hard refresh browser (Ctrl+Shift+R) to load the new panel."
            info "Welcome to Jexactyl! 🎉"
            
            pause
            ;;
            
        0)
            show_banner
            echo -e "${CYAN}Thanks for using Ray Pterodactyl Manager! Exiting...${NC}"
            exit 0
            ;;
            
        *) 
            err "Invalid option. Please choose a number between 0 and 10."
            sleep 1 
            ;;
    esac
done
