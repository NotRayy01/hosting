#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Cloudflared Installer (Pro Edition)
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

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Cloudflared Installer "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# 🛡️ INIT & CHECKS
# ==============================================================================
show_banner

if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
    info "Running with sudo privileges..."
fi

if command -v cloudflared >/dev/null 2>&1; then
    warn "cloudflared is already installed!"
    info "Version: $(cloudflared --version)"
    echo ""
    ok "Nothing to do – you're good to go!"
    exit 0
fi

# ==============================================================================
# 📦 INSTALLATION PROCESS
# ==============================================================================
step "Ensuring keyrings directory exists..."
$SUDO mkdir -p --mode=0755 /usr/share/keyrings
ok "Keyrings directory verified."

step "Adding Cloudflare GPG key..."
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | \
    $SUDO tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
ok "GPG key added."

step "Configuring Cloudflare repository..."
REPO_LINE="deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main"
REPO_FILE="/etc/apt/sources.list.d/cloudflared.list"

if ! grep -qF "$REPO_LINE" "$REPO_FILE" 2>/dev/null; then
    echo "$REPO_LINE" | $SUDO tee "$REPO_FILE" >/dev/null
    ok "Repository added to sources."
else
    info "Repository already configured."
fi

step "Updating package list and installing cloudflared..."
$SUDO apt-get update -qq
$SUDO apt-get install -y cloudflared

# ==============================================================================
# 🎉 VERIFICATION
# ==============================================================================
echo ""
if command -v cloudflared >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}             ✨ INSTALLATION SUCCESSFUL ✨                      ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo ""
    ok "cloudflared installed successfully!"
    info "Version: $(cloudflared --version)"
    echo ""
    info "Run 'cloudflared' to get started."
    echo -e "${MAGENTA}${BOLD}Thank you for using Ray Hosting Manager! 🚀${NC}"
    echo ""
else
    err "Installation failed – please check the output above."
    exit 1
fi
