#!/bin/bash
set -e



RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"

fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source <(curl -sSL "$RAY_REPO/lib/lib.sh")
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

export FQDN=""
export MYSQL_DB=""
export MYSQL_USER=""
export MYSQL_PASSWORD=""
export timezone=""
export email=""
export user_email=""
export user_username=""
export user_firstname=""
export user_lastname=""
export user_password=""
export ASSUME_SSL=false
export CONFIGURE_LETSENCRYPT=false
export CONFIGURE_FIREWALL=false

ask_letsencrypt() {
  echo -e -n " ${CYAN}➤${NC} Auto-configure HTTPS with Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL
  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
    ASSUME_SSL=false
  fi
}

ask_assume_ssl() {
  echo -e -n " ${CYAN}➤${NC} Assume SSL (manual cert installation)? (y/N): "
  read -r ASSUME_SSL_INPUT
  [[ "$ASSUME_SSL_INPUT" =~ [Yy] ]] && ASSUME_SSL=true
  true
}

check_FQDN_SSL() {
  if [[ $(invalid_ip "$FQDN") == 1 && $FQDN != 'localhost' ]]; then
    SSL_AVAILABLE=true
  else
    warn "Let's Encrypt disabled: IP address used instead of valid Domain."
  fi
}

main() {
  if [ -d "/var/www/pterodactyl" ]; then
    warn "Pterodactyl panel already exists on this server!"
    echo -e -n " ${CYAN}➤${NC} Proceed anyway? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then err "Installation aborted!"; exit 1; fi
  fi

  welcome "panel"
  check_os_x86_64

  step "Database Configuration"
  MYSQL_DB="-"
  while [[ "$MYSQL_DB" == *"-"* ]]; do
    required_input MYSQL_DB "Database name [panel]: " "" "panel"
  done

  MYSQL_USER="-"
  while [[ "$MYSQL_USER" == *"-"* ]]; do
    required_input MYSQL_USER "Database username [pterodactyl]: " "" "pterodactyl"
  done

  rand_pw=$(gen_passwd 64)
  password_input MYSQL_PASSWORD "Database password [auto-generate]: " "Required" "$rand_pw"

  step "Panel Settings"
  readarray -t valid_timezones <<<"$(curl -s "$RAY_REPO/configs/valid_timezones.txt")"
  while [ -z "$timezone" ]; do
    echo -e -n " ${CYAN}➤${NC} Select timezone [Europe/London]: "
    read -r timezone_input
    array_contains_element "$timezone_input" "${valid_timezones[@]}" && timezone="$timezone_input"
    [ -z "$timezone_input" ] && timezone="Europe/London"
  done

  email_input email "System Email (for Let's Encrypt): " "Invalid email"

  step "Admin Account"
  email_input user_email "Admin Email: " "Invalid email"
  required_input user_username "Admin Username: " "Required"
  required_input user_firstname "First Name: " "Required"
  required_input user_lastname "Last Name: " "Required"
  password_input user_password "Admin Password: " "Required"

  step "Network Settings"
  while [ -z "$FQDN" ]; do
    echo -e -n " ${CYAN}➤${NC} Panel FQDN (e.g. panel.domain.com): "
    read -r FQDN
    [ -z "$FQDN" ] && err "FQDN is required"
  done

  check_FQDN_SSL
  ask_firewall CONFIGURE_FIREWALL

  if [ "$SSL_AVAILABLE" == true ]; then
    ask_letsencrypt
    [ "$CONFIGURE_LETSENCRYPT" == false ] && ask_assume_ssl
  fi

  [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ] && bash <(curl -s "$RAY_REPO/lib/verify-fqdn.sh") "$FQDN"

  summary

  echo -e -n "\n${MAGENTA}⚡ ${BOLD}Ready to install? (y/N): ${NC}"
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "panel"
  else
    err "Installation aborted."
    exit 1
  fi
}

summary() {
  echo ""
  print_brake
  echo -e " ${BOLD}📊 INSTALLATION SUMMARY${NC}"
  print_brake
  echo -e " ${CYAN}Domain:${NC} $FQDN"
  echo -e " ${CYAN}Database:${NC} $MYSQL_DB | User: $MYSQL_USER"
  echo -e " ${CYAN}Admin User:${NC} $user_username ($user_email)"
  echo -e " ${CYAN}Timezone:${NC} $timezone"
  echo -e " ${CYAN}UFW/Firewall:${NC} $CONFIGURE_FIREWALL"
  echo -e " ${CYAN}Let's Encrypt SSL:${NC} $CONFIGURE_LETSENCRYPT"
  print_brake
}

goodbye() {
  echo ""
  print_brake
  echo -e " ${BOLD}✨ PTERODACTYL PANEL INSTALLED ✨${NC}"
  print_brake
  [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == false ] && echo -e " ${GREEN}URL: https://$FQDN${NC}"
  echo -e " ${YELLOW}Welcome to the Ray Development Empire.${NC}"
  print_brake
}

main
goodbye