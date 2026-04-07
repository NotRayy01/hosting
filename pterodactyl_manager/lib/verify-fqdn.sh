#!/bin/bash
set -e


RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"

fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source <(curl -sSL "$RAY_REPO/lib/lib.sh")
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

CHECKIP_URL="https://checkip.pterodactyl-installer.se"
DNS_SERVER="8.8.8.8"

if [[ $EUID -ne 0 ]]; then err "Must execute as root."; exit 1; fi

fail() {
  warn "DNS Record ($dns_record) does not match your server IP ($ip)!"
  info "Make sure $fqdn is pointing to $ip."
  info "If using Cloudflare, disable the proxy (Orange Cloud) during installation."

  echo -e -n " ${CYAN}➤${NC} Proceed anyway? (Warning: Certbot may fail) (y/N): "
  read -r override
  [[ ! "$override" =~ [Yy] ]] && err "Invalid FQDN or DNS record" && exit 1
  return 0
}

dep_install() {
  update_repos true
  case "$OS" in
  ubuntu | debian) install_packages "dnsutils" true ;;
  rocky | almalinux) install_packages "bind-utils" true ;;
  esac
  return 0
}

confirm() {
  info "Verifying IP via $CHECKIP_URL (Official Pterodactyl Checker)"
  echo -e -n " ${CYAN}➤${NC} Allow HTTPS IP check? (y/N): "
  read -r confirm
  [[ "$confirm" =~ [Yy] ]] || (err "Verification aborted" && false)
}

dns_verify() {
  step "Resolving DNS for $fqdn..."
  ip=$(curl -4 -s $CHECKIP_URL)
  dns_record=$(dig +short @$DNS_SERVER "$fqdn" | tail -n1)
  [ "${ip}" != "${dns_record}" ] && fail
  ok "DNS verified successfully!"
}

main() {
  fqdn="$1"
  dep_install
  confirm && dns_verify
  true
}

main "$1" "$2"