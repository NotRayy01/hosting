#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray GitHub VM Installer (Codespace-to-VPS)
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
    echo -e "\n${CYAN}Press [ENTER] to return to the menu...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray GitHub VM Installer (Codespace-to-VPS) "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# 🛡️ INIT & ENVIRONMENT CHECKS
# ==============================================================================
# Check if sudo is available
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

# ==============================================================================
# 🛠️ MODULE 1: SETUP SSH SERVER
# ==============================================================================
setup_ssh() {
    show_banner
    echo -e "${MAGENTA}--- 🔐 Setup Codespace SSH Server ---${NC}"

    step "Updating packages and installing OpenSSH Server..."
    $SUDO apt-get update -y -qq
    $SUDO apt-get install -y openssh-server -qq
    $SUDO mkdir -p /run/sshd
    ok "OpenSSH Server installed."

    step "Configure User Password"
    info "You need a password to connect remotely."
    info "Setting password for user: ${BOLD}$(whoami)${NC}"
    echo ""
    $SUDO passwd "$(whoami)"
    echo ""
    ok "Password updated."

    step "Configuring SSHd to allow password authentication..."
    $SUDO sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    $SUDO sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    
    info "Restarting SSH Service..."
    $SUDO service ssh restart >/dev/null 2>&1 || $SUDO /usr/sbin/sshd
    
    ok "SSH Server is configured and running on port 22!"
    pause
}

# ==============================================================================
# 🌐 MODULE 2: CLOUDFLARE TUNNEL (Expose SSH)
# ==============================================================================
expose_ssh_cloudflared() {
    show_banner
    echo -e "${MAGENTA}--- 🌐 Expose SSH via Cloudflare Tunnel ---${NC}"

    step "Checking for Cloudflared..."
    if ! command -v cloudflared >/dev/null 2>&1; then
        info "Installing Cloudflared..."
        curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
        chmod +x cloudflared
        $SUDO mv cloudflared /usr/local/bin/
        ok "Cloudflared installed."
    else
        ok "Cloudflared is already installed."
    fi

    step "Starting Cloudflare Quick Tunnel for Port 22..."
    # Kill any existing quick tunnels
    pkill cloudflared || true
    
    # Start the tunnel in the background
    nohup cloudflared tunnel --url tcp://localhost:22 > /tmp/cloudflared.log 2>&1 &
    
    info "Waiting for tunnel to establish (this takes a few seconds)..."
    sleep 5
    
    # Extract the URL from the log
    TUNNEL_URL=$(grep -o 'tcp://[a-zA-Z0-9.-]*' /tmp/cloudflared.log | head -1 || true)

    if [ -n "$TUNNEL_URL" ]; then
        echo ""
        echo -e "${GREEN}${BOLD}================================================================${NC}"
        echo -e "${GREEN}${BOLD}              🚀 TUNNEL ESTABLISHED 🚀                          ${NC}"
        echo -e "${GREEN}${BOLD}================================================================${NC}"
        echo ""
        info "Your GitHub Codespace is now acting as a remote VPS!"
        echo ""
        echo -e "${YELLOW}${BOLD}Connect from ANY terminal using this command:${NC}"
        # Remove 'tcp://' from the output for the SSH command
        CLEAN_URL="${TUNNEL_URL#tcp://}"
        echo -e "${CYAN}${BOLD}ssh $(whoami)@${CLEAN_URL}${NC}"
        echo ""
        warn "Note: Cloudflare Quick Tunnels drop if inactive. Run this again if it disconnects."
    else
        err "Failed to extract Tunnel URL. Check /tmp/cloudflared.log for details."
    fi
    pause
}

# ==============================================================================
# 📋 MAIN MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${YELLOW}🎛️  GitHub Codespace -> VPS Converter${NC}"
    echo "1) 🔐 Step 1: Install SSH & Set Password"
    echo "2) 🌐 Step 2: Expose SSH via Cloudflare (Get Remote IP)"
    echo "0) ❌ Exit to Main Menu"
    echo ""
    
    read -p "Select Option [0-2]: " choice

    case "$choice" in
        1) setup_ssh ;;
        2) expose_ssh_cloudflared ;;
        0)
            show_banner
            ok "Exiting GitHub VM Installer."
            exit 0
            ;;
        *)
            err "Invalid option! Please enter 0, 1, or 2."
            sleep 2
            ;;
    esac
done
