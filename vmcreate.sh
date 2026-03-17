#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ray Development Management Console (Pro Edition)
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

pause() {
    echo -e "\n${CYAN}Press [ENTER] to continue...${NC}"
    read -r -s
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================"
    echo " 🚀 Ray Development Management Console "
    echo " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
    echo "================================================================${NC}"
    echo ""
}

# ==============================================================================
# 🛠️ MODULE 1: IDX TOOL SETUP
# ==============================================================================
idx_tool_setup() {
    show_banner
    echo -e "${MAGENTA}--- 🛠️ IDX Tool Setup (Nix + QEMU) ---${NC}"

    step "Initializing workspace cleanup..."
    cd ~ || exit 1
    rm -rf myapp flutter 2>/dev/null
    ok "Old workspace files cleaned."

    step "Creating Workspace Directory..."
    mkdir -p vps123
    cd vps123

    if [ ! -d ".idx" ]; then
        step "Creating IDX development environment..."
        mkdir -p .idx
        cd .idx

        info "Generating dev.nix configuration..."
        cat > dev.nix << 'EOF'
{ pkgs, ... }: {
  channel = "stable-24.05";

  packages = with pkgs; [
    unzip
    openssh
    git
    qemu_kvm
    sudo
    cdrkit
    cloud-utils
    qemu
    flutter
    dart
  ];

  env = {
    EDITOR = "nano";
  };

  idx = {
    extensions = [
      "Dart-Code.flutter"
      "Dart-Code.dart-code"
    ];
    workspace = {
      onCreate = {};
      onStart = {};
    };
    previews = {
      enable = true;
    };
  };
}
EOF
        echo ""
        ok "IDX Tool Setup Complete!"
        echo -e "${BOLD}Location:${NC} ~/vps123/.idx"
        echo -e "${BOLD}Channel:${NC}  Nix Stable 24.05"
        echo -e "${BOLD}Tools:${NC}    Flutter, Dart, QEMU, Git, SSH"
    else
        echo ""
        warn "IDX environment already exists!"
        echo -e "Path: ~/vps123/.idx"
    fi
    pause
}

# ==============================================================================
# 🖥️ MODULE 2: IDX VPS MAKER
# ==============================================================================
idx_vps_maker() {
    show_banner
    echo -e "${MAGENTA}--- 🖥️ IDX VPS Maker (Remote Deployment) ---${NC}"
    
    step "Launching Ray Cloud VM Manager..."
    info "Streaming the latest version from GitHub..."
    echo ""

    if command -v curl >/dev/null 2>&1; then
        if bash <(curl -s https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/vm.sh); then
            ok "Cloud VM Manager session completed successfully."
        else
            err "Failed to fetch or execute the script."
            warn "Check your internet connection or GitHub status."
        fi
    else
        err "curl is not installed."
        info "Install it with: sudo apt install curl (or equivalent)"
    fi
    pause
}

# ==============================================================================
# 🐙 MODULE 3: GITHUB VM INSTALLER
# ==============================================================================
github_vm_installer() {
    show_banner
    echo -e "${MAGENTA}--- 🐙 Install VM in GitHub (Codespaces) ---${NC}"
    
    step "Launching Ray GitHub VM Installer..."
    info "Preparing GitHub Codespaces/Actions environment..."
    echo ""

    if command -v curl >/dev/null 2>&1; then
        # NOTE: Replace the URL below with your actual GitHub VM script URL if different
        if bash <(curl -s https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/github_vm.sh); then
            ok "GitHub VM Installation completed successfully."
        else
            err "Failed to fetch or execute the GitHub VM script."
            warn "Ensure you are in a valid GitHub environment and check the repo URL."
        fi
    else
        err "curl is not installed."
        info "Install it with: sudo apt install curl"
    fi
    pause
}

# ==============================================================================
# 📋 MAIN MENU LOOP
# ==============================================================================
while true; do
    show_banner
    echo -e "${YELLOW}🎛️  Development Management Console${NC}"
    echo "1) 🛠️  IDX Tool Setup (Nix + QEMU Environment)"
    echo "2) 🖥️  IDX VPS Maker (Remote Deployment)"
    echo "3) 🐙 Install VM in GitHub (Codespaces)"
    echo "0) ❌ Exit Console"
    echo ""
    
    read -p "Select Option [0-3]: " op

    case "$op" in
        1) idx_tool_setup ;;
        2) idx_vps_maker ;;
        3) github_vm_installer ;;
        0)
            show_banner
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo -e "${GREEN}${BOLD}              SESSION TERMINATED                                ${NC}"
            echo -e "${GREEN}${BOLD}================================================================${NC}"
            echo ""
            info "Thank you for using the Ray Development Management Console!"
            info "See you in the next session, Operator! 🚀"
            echo ""
            exit 0
            ;;
        *)
            err "Please enter a valid option (0-3)."
            sleep 2
            ;;
    esac
done
