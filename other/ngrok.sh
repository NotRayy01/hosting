#!/bin/bash

# ============================================================
#   NGROK AUTO SETUP SCRIPT — by RayNode
#   For Pterodactyl Wings / General Use
# ============================================================

# ──────────────────────────────────────────────
#  COLORS & STYLES
# ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'

# ──────────────────────────────────────────────
#  SPINNER
# ──────────────────────────────────────────────
spinner() {
    local pid=$1
    local msg=$2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${RESET}  ${WHITE}${msg}${RESET}   "
        i=$(( (i+1) % 10 ))
        sleep 0.08
    done
    printf "\r  ${GREEN}✔${RESET}  ${WHITE}${msg}${RESET}   \n"
}

# ──────────────────────────────────────────────
#  BANNER
# ──────────────────────────────────────────────
clear
echo ""
echo -e "${MAGENTA}${BOLD}"
echo "  ███╗   ██╗ ██████╗ ██████╗  ██████╗ ██╗  ██╗"
echo "  ████╗  ██║██╔════╝ ██╔══██╗██╔═══██╗██║ ██╔╝"
echo "  ██╔██╗ ██║██║  ███╗██████╔╝██║   ██║█████╔╝ "
echo "  ██║╚██╗██║██║   ██║██╔══██╗██║   ██║██╔═██╗ "
echo "  ██║ ╚████║╚██████╔╝██║  ██║╚██████╔╝██║  ██╗"
echo "  ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝"
echo -e "${RESET}"
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${WHITE}${BOLD}  Auto Setup Script  ${RESET}${DIM}| Pterodactyl Wings Edition${RESET}"
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
sleep 1

# ──────────────────────────────────────────────
#  ROOT CHECK
# ──────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "  ${RED}✖  Please run as root (sudo su)${RESET}"
    exit 1
fi

# ──────────────────────────────────────────────
#  STEP 1: USER INPUTS
# ──────────────────────────────────────────────
echo -e "  ${BG_MAGENTA}${WHITE}${BOLD}  STEP 1 — Configuration  ${RESET}"
echo ""

echo -e "  ${YELLOW}🔑  Enter your ngrok Auth Token:${RESET}"
echo -e "  ${DIM}(Get it from: https://dashboard.ngrok.com/get-started/your-authtoken)${RESET}"
echo -ne "  ${CYAN}❯ ${RESET}"
read -r NGROK_TOKEN

if [ -z "$NGROK_TOKEN" ]; then
    echo -e "  ${RED}✖  Auth token cannot be empty!${RESET}"
    exit 1
fi

echo ""
echo -e "  ${YELLOW}🌐  Do you have a static ngrok domain? (y/n):${RESET}"
echo -ne "  ${CYAN}❯ ${RESET}"
read -r HAS_DOMAIN

NGROK_DOMAIN=""
if [[ "$HAS_DOMAIN" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "  ${YELLOW}🔗  Enter your static ngrok domain:${RESET}"
    echo -e "  ${DIM}(e.g: your-domain.ngrok-free.app)${RESET}"
    echo -ne "  ${CYAN}❯ ${RESET}"
    read -r NGROK_DOMAIN
fi

echo ""
echo -e "  ${YELLOW}🔌  Enter the port to tunnel:${RESET}"
echo -e "  ${DIM}(Default: 8080 for Wings | 80 for general web)${RESET}"
echo -ne "  ${CYAN}❯ ${RESET}"
read -r NGROK_PORT

if [ -z "$NGROK_PORT" ]; then
    NGROK_PORT=8080
fi

echo ""
echo -e "  ${GREEN}✔  Config saved!${RESET}"
echo ""
sleep 0.5

# ──────────────────────────────────────────────
#  STEP 2: INSTALL NGROK
# ──────────────────────────────────────────────
echo -e "  ${BG_CYAN}${WHITE}${BOLD}  STEP 2 — Installing ngrok  ${RESET}"
echo ""

if command -v ngrok &>/dev/null; then
    echo -e "  ${GREEN}✔  ngrok already installed — skipping${RESET}"
else
    echo -e "  ${BLUE}⬇  Downloading ngrok binary...${RESET}"
    (curl -Lo /tmp/ngrok.zip https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -s) &
    spinner $! "Downloading ngrok..."

    (unzip -o /tmp/ngrok.zip -d /usr/local/bin > /dev/null 2>&1) &
    spinner $! "Extracting..."

    chmod +x /usr/local/bin/ngrok

    if ! command -v ngrok &>/dev/null; then
        export PATH=$PATH:/usr/local/bin
        echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
    fi

    echo -e "  ${GREEN}✔  ngrok installed successfully!${RESET}"
fi

echo ""
sleep 0.5

# ──────────────────────────────────────────────
#  STEP 3: AUTHENTICATE
# ──────────────────────────────────────────────
echo -e "  ${BG_BLUE}${WHITE}${BOLD}  STEP 3 — Authenticating ngrok  ${RESET}"
echo ""

(/usr/local/bin/ngrok config add-authtoken "$NGROK_TOKEN" > /dev/null 2>&1) &
spinner $! "Adding auth token..."

echo -e "  ${GREEN}✔  Auth token configured!${RESET}"
echo ""
sleep 0.5

# ──────────────────────────────────────────────
#  STEP 4: CREATE SYSTEMD SERVICE
# ──────────────────────────────────────────────
echo -e "  ${BG_MAGENTA}${WHITE}${BOLD}  STEP 4 — Setting up systemd service  ${RESET}"
echo ""

if [ -n "$NGROK_DOMAIN" ]; then
    EXEC_CMD="/usr/local/bin/ngrok http --domain=${NGROK_DOMAIN} ${NGROK_PORT}"
else
    EXEC_CMD="/usr/local/bin/ngrok http ${NGROK_PORT}"
fi

cat > /etc/systemd/system/ngrok.service <<EOF
[Unit]
Description=ngrok Tunnel Service
After=network.target

[Service]
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=5
User=root
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

(systemctl daemon-reload > /dev/null 2>&1) &
spinner $! "Reloading systemd..."

(systemctl enable ngrok > /dev/null 2>&1) &
spinner $! "Enabling ngrok service..."

(systemctl restart ngrok > /dev/null 2>&1) &
spinner $! "Starting ngrok..."

sleep 4

echo -e "  ${GREEN}✔  ngrok service is running!${RESET}"
echo ""
sleep 0.5

# ──────────────────────────────────────────────
#  STEP 5: GET TUNNEL URL
# ──────────────────────────────────────────────
echo -e "  ${BG_CYAN}${WHITE}${BOLD}  STEP 5 — Fetching Tunnel URL  ${RESET}"
echo ""

MAX_WAIT=15
WAITED=0
TUNNEL_URL=""

while [ -z "$TUNNEL_URL" ] && [ $WAITED -lt $MAX_WAIT ]; do
    sleep 1
    WAITED=$((WAITED+1))
    TUNNEL_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])
    if tunnels:
        print(tunnels[0]['public_url'])
except:
    pass
" 2>/dev/null)
done

echo ""
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [ -n "$TUNNEL_URL" ]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}🎉  Tunnel is LIVE!${RESET}"
    echo ""
    echo -e "  ${WHITE}${BOLD}  Tunnel URL:${RESET}"
    echo -e "  ${YELLOW}${BOLD}  ➜  ${TUNNEL_URL}${RESET}"
    echo ""
    # Extract hostname
    TUNNEL_HOST=$(echo "$TUNNEL_URL" | sed 's|https://||' | sed 's|http://||')
    echo -e "  ${WHITE}  FQDN (for panel): ${CYAN}${BOLD}${TUNNEL_HOST}${RESET}"
else
    echo ""
    echo -e "  ${RED}✖  Could not fetch URL automatically.${RESET}"
    echo -e "  ${YELLOW}  Run manually: ${WHITE}curl -s http://localhost:4040/api/tunnels | python3 -m json.tool${RESET}"
fi

echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ──────────────────────────────────────────────
#  PTERODACTYL NOTE
# ──────────────────────────────────────────────
echo -e "  ${BG_MAGENTA}${WHITE}${BOLD}  📋  Pterodactyl Wings Setup Guide  ${RESET}"
echo ""
echo -e "  ${YELLOW}${BOLD}Step 1${RESET} — Edit Wings config:"
echo -e "  ${DIM}  nano /etc/pterodactyl/config.yml${RESET}"
echo ""
echo -e "  ${YELLOW}${BOLD}Step 2${RESET} — Set these values in config.yml:"
echo ""
echo -e "  ${CYAN}  api:"
echo -e "    host: 0.0.0.0"
echo -e "    port: ${NGROK_PORT}          ${DIM}← same as tunnel port${RESET}${CYAN}"
echo -e "    ssl:"
echo -e "      enabled: false     ${DIM}← ngrok handles SSL${RESET}${CYAN}"
echo -e "      cert: \"\""
echo -e "      key: \"\"${RESET}"
echo ""
echo -e "  ${YELLOW}${BOLD}Step 3${RESET} — Restart Wings:"
echo -e "  ${DIM}  systemctl restart wings${RESET}"
echo ""
echo -e "  ${YELLOW}${BOLD}Step 4${RESET} — In Pterodactyl Panel → Admin → Nodes → Create/Edit Node:"
echo ""
echo -e "  ${WHITE}  ┌─────────────────────────────────────────────┐${RESET}"
if [ -n "$TUNNEL_HOST" ]; then
echo -e "  ${WHITE}  │ ${CYAN}FQDN        ${WHITE}→ ${GREEN}${TUNNEL_HOST}${RESET}"
fi
echo -e "  ${WHITE}  │ ${CYAN}Scheme      ${WHITE}→ ${GREEN}https${RESET}"
echo -e "  ${WHITE}  │ ${CYAN}Port        ${WHITE}→ ${GREEN}443${RESET}"
echo -e "  ${WHITE}  │ ${CYAN}Behind Proxy${WHITE}→ ${GREEN}✅ Yes${RESET}"
echo -e "  ${WHITE}  │ ${CYAN}Daemon Port ${WHITE}→ ${GREEN}443${RESET}"
echo -e "  ${WHITE}  └─────────────────────────────────────────────┘${RESET}"
echo ""
echo -e "  ${YELLOW}${BOLD}Step 5${RESET} — Copy Wings token from panel and paste in config.yml"
echo ""
echo -e "  ${RED}${BOLD}  ⚠  Important Notes:${RESET}"
echo -e "  ${DIM}  • SFTP (port 2022) requires ngrok paid plan for TCP tunnels${RESET}"
echo -e "  ${DIM}  • Free ngrok = 1 static domain allowed${RESET}"
echo -e "  ${DIM}  • If URL changes, update node FQDN in panel${RESET}"
echo -e "  ${DIM}  • Run 'systemctl status ngrok' to check tunnel health${RESET}"
echo ""
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${GREEN}${BOLD}  ✅  Setup Complete! Good luck bhai 🚀${RESET}"
echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
