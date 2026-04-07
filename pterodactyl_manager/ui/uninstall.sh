#!/bin/bash
set -e


RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"

fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source <(curl -sSL "$RAY_REPO/lib/lib.sh")
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #
export RM_PANEL=false
export RM_WINGS=false

# --------------- Main functions --------------- #

main() {
  clear
  print_brake
  echo -e "${BOLD} 🗑️ Ray Pterodactyl Uninstaller ${NC}"
  echo -e " 👑 Developed by Ray | 🏢 Ray Industries"
  print_brake

  if [ -d "/var/www/pterodactyl" ]; then
    info "Panel installation has been detected."
    echo -e -n " ${CYAN}➤${NC} Do you want to remove the Panel? (y/N): "
    read -r RM_PANEL_INPUT
    [[ "$RM_PANEL_INPUT" =~ [Yy] ]] && RM_PANEL=true
  fi

  if [ -d "/etc/pterodactyl" ]; then
    echo ""
    info "Wings installation has been detected."
    warn "THIS WILL REMOVE ALL SERVERS AND CONTAINERS!"
    echo -e -n " ${CYAN}➤${NC} Do you want to remove Wings (daemon)? (y/N): "
    read -r RM_WINGS_INPUT
    [[ "$RM_WINGS_INPUT" =~ [Yy] ]] && RM_WINGS=true
  fi

  if [ "$RM_PANEL" == false ] && [ "$RM_WINGS" == false ]; then
    err "Nothing selected to uninstall!"
    exit 1
  fi

  summary

  echo -e -n "\n ${RED}➤${NC} ${BOLD}Continue with uninstallation? (y/N): ${NC}"
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "uninstall"
  else
    err "Uninstallation aborted."
    exit 1
  fi
}

summary() {
  echo ""
  print_brake
  echo -e " ${BOLD}🗑️ UNINSTALLATION SUMMARY${NC}"
  print_brake
  echo -e " ${CYAN}Uninstall Panel:${NC} $RM_PANEL"
  echo -e " ${CYAN}Uninstall Wings:${NC} $RM_WINGS"
  print_brake
}

goodbye() {
  echo ""
  print_brake
  [ "$RM_PANEL" == true ] && ok "Panel uninstallation completed."
  [ "$RM_WINGS" == true ] && ok "Wings uninstallation completed."
  echo -e " ${YELLOW}System cleaned. Thank you for using Ray Industries.${NC}"
  print_brake
}

main
goodbye