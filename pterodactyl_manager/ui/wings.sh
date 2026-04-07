#!/bin/bash
set -e


RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"

fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source <(curl -sSL "$RAY_REPO/lib/lib.sh")
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #
export INSTALL_MARIADB=false
export CONFIGURE_FIREWALL=false
export CONFIGURE_LETSENCRYPT=false
export FQDN=""
export EMAIL=""
export CONFIGURE_DBHOST=false
export CONFIGURE_DB_FIREWALL=false
export MYSQL_DBHOST_HOST="127.0.0.1"
export MYSQL_DBHOST_USER="pterodactyluser"
export MYSQL_DBHOST_PASSWORD=""

# ------------ User input functions ------------ #

ask_letsencrypt() {
  if [ "$CONFIGURE_FIREWALL" == false ]; then
    warn "Let's Encrypt requires port 80/443 to be opened! You opted out of auto-firewall."
  fi
  warn "Let's Encrypt requires a valid FQDN (e.g. node.example.com), not an IP address."
  
  echo -e -n " ${CYAN}➤${NC} Auto-configure HTTPS with Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL
  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
  fi
}

ask_database_user() {
  echo -e -n " ${CYAN}➤${NC} Auto-configure a database user for this host? (y/N): "
  read -r CONFIRM_DBHOST
  if [[ "$CONFIRM_DBHOST" =~ [Yy] ]]; then
    ask_database_external
    CONFIGURE_DBHOST=true
  fi
}

ask_database_external() {
  echo -e -n " ${CYAN}➤${NC} Configure MySQL for external access? (y/N): "
  read -r CONFIRM_DBEXTERNAL
  if [[ "$CONFIRM_DBEXTERNAL" =~ [Yy] ]]; then
    echo -e -n " ${CYAN}➤${NC} Enter the Panel IP address (leave blank for any %): "
    read -r CONFIRM_DBEXTERNAL_HOST
    if [ -z "$CONFIRM_DBEXTERNAL_HOST" ]; then
      MYSQL_DBHOST_HOST="%"
    else
      MYSQL_DBHOST_HOST="$CONFIRM_DBEXTERNAL_HOST"
    fi
    [ "$CONFIGURE_FIREWALL" == true ] && ask_database_firewall
    return 0
  fi
}

ask_database_firewall() {
  warn "Allowing incoming traffic to port 3306 (MySQL) is a security risk!"
  echo -e -n " ${CYAN}➤${NC} Allow incoming traffic to port 3306? (y/N): "
  read -r CONFIRM_DB_FIREWALL
  if [[ "$CONFIRM_DB_FIREWALL" =~ [Yy] ]]; then
    CONFIGURE_DB_FIREWALL=true
  fi
}

####################
## MAIN FUNCTIONS ##
####################

main() {
  if [ -d "/etc/pterodactyl" ]; then
    warn "Pterodactyl Wings already exists on this server!"
    echo -e -n " ${CYAN}➤${NC} Proceed anyway? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then err "Installation aborted!"; exit 1; fi
  fi

  welcome "wings"
  check_virt

  echo -e " ${CYAN}ℹ️  The installer will deploy Docker and Pterodactyl Wings.${NC}"
  echo -e " ${CYAN}ℹ️  You must still create the Node on your Panel and paste the config here later.${NC}"
  print_brake

  ask_firewall CONFIGURE_FIREWALL
  ask_database_user

  if [ "$CONFIGURE_DBHOST" == true ]; then
    type mysql >/dev/null 2>&1 && HAS_MYSQL=true || HAS_MYSQL=false
    if [ "$HAS_MYSQL" == false ]; then INSTALL_MARIADB=true; fi

    MYSQL_DBHOST_USER="-"
    while [[ "$MYSQL_DBHOST_USER" == *"-"* ]]; do
      required_input MYSQL_DBHOST_USER "Database host username [pterodactyluser]: " "" "pterodactyluser"
    done
    password_input MYSQL_DBHOST_PASSWORD "Database host password: " "Password cannot be empty"
  fi

  ask_letsencrypt

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    while [ -z "$FQDN" ]; do
      echo -e -n " ${CYAN}➤${NC} FQDN for Let's Encrypt (node.example.com): "
      read -r FQDN
      ASK=false

      [ -z "$FQDN" ] && err "FQDN is required"
      bash <(curl -s "$RAY_REPO/lib/verify-fqdn.sh") "$FQDN" || ASK=true
      [ -d "/etc/letsencrypt/live/$FQDN/" ] && err "Certificate already exists!" && ASK=true

      if [ "$ASK" == true ]; then
        FQDN=""
        echo -e -n " ${CYAN}➤${NC} Still auto-configure HTTPS with Let's Encrypt? (y/N): "
        read -r CONFIRM_SSL
        if [[ ! "$CONFIRM_SSL" =~ [Yy] ]]; then CONFIGURE_LETSENCRYPT=false; FQDN=""; fi
      fi
    done

    if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
      while ! valid_email "$EMAIL"; do
        echo -e -n " ${CYAN}➤${NC} Email for Let's Encrypt: "
        read -r EMAIL
        valid_email "$EMAIL" || err "Invalid email"
      done
    fi
  fi

  echo ""
  print_brake
  echo -e -n " ${MAGENTA}⚡ ${BOLD}Ready to install Wings? (y/N): ${NC}"
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "wings"
  else
    err "Installation aborted."
    exit 1
  fi
}

goodbye() {
  echo ""
  print_brake
  echo -e " ${BOLD}✨ PTERODACTYL WINGS INSTALLED ✨${NC}"
  print_brake
  echo -e " ${CYAN}Next Steps:${NC}"
  echo -e " 1. Create a Node on your Pterodactyl Panel."
  echo -e " 2. Click 'Auto Deploy' or paste the config into ${BOLD}/etc/pterodactyl/config.yml${NC}"
  echo -e " 3. Verify Wings is working: ${BOLD}sudo wings${NC}"
  echo -e " 4. Start the Daemon: ${BOLD}systemctl enable --now wings${NC}"
  print_brake
  echo ""
}

main
goodbye