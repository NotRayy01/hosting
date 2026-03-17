#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Pterodactyl Wings Installer (Pro Edition)
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

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Pterodactyl Wings Setup "
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

info "Starting Pterodactyl Wings Installation..."

# ==============================================================================
# 🐋 1. DOCKER
# ==============================================================================
step "Installing Docker..."
curl -sSL https://get.docker.com/ | CHANNEL=stable bash > /dev/null 2>&1
ok "Docker installed successfully."

info "Starting Docker service..."
sudo systemctl enable --now docker > /dev/null 2>&1
ok "Docker service started and enabled."

# ==============================================================================
# ⚙️ 2. SYSTEM OPTIMIZATION (GRUB)
# ==============================================================================
step "System Optimization (GRUB)..."
if [ -f "/etc/default/grub" ]; then
    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="swapaccount=1"/' /etc/default/grub
    sudo update-grub > /dev/null 2>&1
    ok "GRUB parameters applied (swapaccount=1)."
else
    warn "GRUB config not found - skipping optimization."
fi

# ==============================================================================
# 🦅 3. INSTALLING WINGS
# ==============================================================================
step "Installing Pterodactyl Wings..."
sudo mkdir -p /etc/pterodactyl
ok "Configuration directory created."

ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" == "aarch64" ]; then
    ARCH="arm64"
else
    err "Unsupported architecture: $ARCH"
    exit 1
fi
info "Architecture detected: ${BOLD}$ARCH${NC}"

info "Downloading latest Wings binary..."
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$ARCH" > /dev/null 2>&1
sudo chmod u+x /usr/local/bin/wings
ok "Wings downloaded and permissions set."

# ==============================================================================
# 🔧 4. SYSTEMD SERVICE
# ==============================================================================
step "Configuring Systemd Service..."
sudo tee /etc/systemd/system/wings.service > /dev/null <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wings > /dev/null 2>&1
ok "Systemd service created and enabled on boot."

# ==============================================================================
# 🔒 5. SSL CERTIFICATE
# ==============================================================================
step "Generating SSL Certificate (Self-Signed)..."
sudo mkdir -p /etc/certs/wing
cd /etc/certs/wing

sudo openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
  -subj "/CN=localhost" -keyout privkey.pem -out fullchain.pem > /dev/null 2>&1
ok "SSL certificate ready (Valid for 10 years)."

# ==============================================================================
# 🛠️ 6. HELPER COMMAND
# ==============================================================================
step "Installing 'wing' helper command..."
sudo tee /usr/local/bin/wing > /dev/null <<'EOF'
#!/usr/bin/env bash
echo -e "\033[0;36m\033[1m"
echo "================================================================"
echo " 🦅 WINGS QUICK COMMANDS | Ray Industries"
echo "================================================================\033[0m"
echo ""
echo -e "\033[0;35m⚡ Start Wings:\033[0m   \033[0;32msudo systemctl start wings\033[0m"
echo -e "\033[0;35m📊 Status:\033[0m        \033[0;32msudo systemctl status wings\033[0m"
echo -e "\033[0;35m📜 Live Logs:\033[0m     \033[0;32mjournalctl -u wings -f\033[0m"
echo ""
echo -e "\033[1;33m⚠️  Important: Map port 8080 → 443 in node settings!\033[0m"
echo ""
EOF
sudo chmod +x /usr/local/bin/wing
ok "'wing' helper command installed!"

# ==============================================================================
# 🎉 COMPLETION & AUTO-CONFIG
# ==============================================================================
echo ""
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}              ✨ WINGS INSTALLATION COMPLETE ✨                 ${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo ""
info "Pterodactyl Wings is fully installed and ready to fly!"
echo -e " ${CYAN}• Auto-configure below, or edit config manually.${NC}"
echo -e " ${CYAN}• Start Wings manually:${NC} ${GREEN}sudo systemctl start wings${NC}"
echo -e " ${CYAN}• Type ${BOLD}wing${NC}${CYAN} anytime for quick commands.${NC}"
echo ""

echo -ne "${YELLOW}🔧 Auto-configure Wings now? [y/N]: ${NC}"
read -r AUTO_CONFIG

if [[ "$AUTO_CONFIG" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${MAGENTA}--- ⚡ Auto Configuration ---${NC}"
    info "Enter your node details from Panel → Nodes → Configuration:"
    echo ""
    
    read -p "📝 UUID: " UUID
    read -p "🔑 Token ID: " TOKEN_ID
    read -p "🔐 Token: " TOKEN
    read -p "🌐 Panel URL (https://...): " REMOTE

    step "Saving configuration..."
    sudo tee /etc/pterodactyl/config.yml > /dev/null <<CFG
debug: false
uuid: ${UUID}
token_id: ${TOKEN_ID}
token: ${TOKEN}
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: true
    cert: /etc/certs/wing/fullchain.pem
    key: /etc/certs/wing/privkey.pem
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_port: 2022
remote: '${REMOTE}'
CFG
    ok "Config saved successfully!"

    step "Launching Wings..."
    sudo systemctl start wings
    ok "Wings is now LIVE! 🦅"

    echo ""
    info "Check status: ${GREEN}systemctl status wings${NC}"
    info "View logs:    ${GREEN}journalctl -u wings -f${NC}"
else
    echo ""
    warn "Auto-config skipped."
    info "Manual steps:"
    echo -e "  ${GREEN}1. Paste configuration into /etc/pterodactyl/config.yml${NC}"
    echo -e "  ${GREEN}2. Run: sudo systemctl start wings${NC}"
fi

echo ""
echo -e "${CYAN}${BOLD}Thank you for using Ray Hosting Manager! 🚀${NC}"
echo ""
